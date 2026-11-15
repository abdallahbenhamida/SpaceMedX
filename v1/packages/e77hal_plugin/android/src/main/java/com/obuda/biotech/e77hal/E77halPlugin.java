package com.obuda.biotech.e77hal;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.os.Build;
import android.provider.Settings;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Small Android helper of the e77hal Flutter plugin. The generic Bluetooth LE
 * work is done by flutter_reactive_ble; this class provides what the Cordova
 * plugin (E77halPlugin.java) did on top of it:
 *
 *  - runtime permissions (BLUETOOTH_SCAN / BLUETOOTH_CONNECT on Android 12+,
 *    location below)                                 [requestRequiredPermissions]
 *  - asking the user to turn Bluetooth on             [enableAction]
 *  - OS bonding (createBond) and bond state events    [bondAction / mBondReceiver]
 *  - location services state / settings
 */
public class E77halPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler,
    ActivityAware, PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener, EventChannel.StreamHandler {

  private static final int REQUEST_BT_ENABLE = 59627;
  private static final int REQUEST_PERMISSIONS = 59630;

  private Context context;
  private Activity activity;
  private ActivityPluginBinding binding;
  private MethodChannel channel;
  private EventChannel events;
  private EventChannel.EventSink sink;
  private BroadcastReceiver bondReceiver;
  private MethodChannel.Result pendingEnable;
  private MethodChannel.Result pendingPermissions;

  // ---- FlutterPlugin --------------------------------------------------------

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding b) {
    context = b.getApplicationContext();
    channel = new MethodChannel(b.getBinaryMessenger(), "e77hal_plugin");
    channel.setMethodCallHandler(this);
    events = new EventChannel(b.getBinaryMessenger(), "e77hal_plugin/bond_events");
    events.setStreamHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding b) {
    channel.setMethodCallHandler(null);
    events.setStreamHandler(null);
    unregisterBondReceiver();
    context = null;
  }

  // ---- ActivityAware --------------------------------------------------------

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding b) {
    attach(b);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    detach();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding b) {
    attach(b);
  }

  @Override
  public void onDetachedFromActivity() {
    detach();
  }

  private void attach(ActivityPluginBinding b) {
    binding = b;
    activity = b.getActivity();
    b.addActivityResultListener(this);
    b.addRequestPermissionsResultListener(this);
  }

  private void detach() {
    if (binding != null) {
      binding.removeActivityResultListener(this);
      binding.removeRequestPermissionsResultListener(this);
    }
    binding = null;
    activity = null;
  }

  // ---- Bluetooth helpers ----------------------------------------------------

  private BluetoothAdapter adapter() {
    BluetoothManager manager =
        (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
    return manager == null ? null : manager.getAdapter();
  }

  /** getRequiredPermissions() of the Cordova plugin. */
  private String[] requiredPermissions() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      return new String[] {
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT
      };
    }
    return new String[] {Manifest.permission.ACCESS_FINE_LOCATION};
  }

  private List<String> missingPermissions() {
    List<String> missing = new ArrayList<>();
    for (String p : requiredPermissions()) {
      if (context.checkSelfPermission(p) != PackageManager.PERMISSION_GRANTED) {
        missing.add(p);
      }
    }
    return missing;
  }

  private boolean locationEnabled() {
    LocationManager lm = (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
    if (lm == null) return true;
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      return lm.isLocationEnabled();
    }
    try {
      return Settings.Secure.getInt(context.getContentResolver(), Settings.Secure.LOCATION_MODE)
          != Settings.Secure.LOCATION_MODE_OFF;
    } catch (Settings.SettingNotFoundException e) {
      return true;
    }
  }

  // ---- MethodChannel --------------------------------------------------------

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    try {
      switch (call.method) {
        case "hasPermissions":
          result.success(missingPermissions().isEmpty());
          break;
        case "requestPermissions":
          requestPermissions(result);
          break;
        case "isBluetoothEnabled": {
          BluetoothAdapter a = adapter();
          result.success(a != null && a.isEnabled());
          break;
        }
        case "requestEnableBluetooth":
          requestEnable(result);
          break;
        case "needsLocationServices":
          result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.S);
          break;
        case "isLocationEnabled":
          result.success(locationEnabled());
          break;
        case "openLocationSettings":
          if (activity != null) {
            activity.startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS));
          }
          result.success(null);
          break;
        case "bondState": {
          BluetoothAdapter a = adapter();
          if (a == null) {
            result.success(BluetoothDevice.BOND_NONE);
            break;
          }
          result.success(a.getRemoteDevice((String) call.arguments).getBondState());
          break;
        }
        case "createBond": {
          BluetoothAdapter a = adapter();
          if (a == null) {
            result.success(false);
            break;
          }
          BluetoothDevice device = a.getRemoteDevice((String) call.arguments);
          result.success(device.createBond());
          break;
        }
        default:
          result.notImplemented();
      }
    } catch (SecurityException e) {
      result.error("permission", "Missing Bluetooth permission: " + e.getMessage(), null);
    } catch (IllegalArgumentException e) {
      result.error("arguments", e.getMessage(), null);
    }
  }

  private void requestPermissions(MethodChannel.Result result) {
    List<String> missing = missingPermissions();
    if (missing.isEmpty()) {
      result.success(true);
      return;
    }
    if (activity == null || pendingPermissions != null) {
      result.success(false);
      return;
    }
    pendingPermissions = result;
    activity.requestPermissions(missing.toArray(new String[0]), REQUEST_PERMISSIONS);
  }

  private void requestEnable(MethodChannel.Result result) {
    BluetoothAdapter a = adapter();
    if (a == null) {
      result.success(false);
      return;
    }
    if (a.isEnabled()) {
      result.success(true);
      return;
    }
    if (activity == null || pendingEnable != null) {
      result.success(false);
      return;
    }
    pendingEnable = result;
    activity.startActivityForResult(
        new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQUEST_BT_ENABLE);
  }

  @Override
  public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
    if (requestCode != REQUEST_BT_ENABLE) return false;
    MethodChannel.Result r = pendingEnable;
    pendingEnable = null;
    if (r != null) {
      BluetoothAdapter a = adapter();
      r.success(a != null && a.isEnabled());
    }
    return true;
  }

  @Override
  public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions,
      @NonNull int[] grantResults) {
    if (requestCode != REQUEST_PERMISSIONS) return false;
    MethodChannel.Result r = pendingPermissions;
    pendingPermissions = null;
    if (r != null) {
      boolean all = grantResults.length > 0;
      for (int g : grantResults) {
        if (g != PackageManager.PERMISSION_GRANTED) all = false;
      }
      r.success(all);
    }
    return true;
  }

  // ---- bond events (mBondReceiver) -----------------------------------------

  @Override
  public void onListen(Object arguments, EventChannel.EventSink events) {
    sink = events;
    if (bondReceiver != null) return;
    bondReceiver = new BroadcastReceiver() {
      @Override
      public void onReceive(Context c, Intent intent) {
        BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
        if (device == null || sink == null) return;
        Map<String, Object> m = new HashMap<>();
        m.put("address", device.getAddress());
        m.put("state", intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, -1));
        m.put("previousState", intent.getIntExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, -1));
        sink.success(m);
      }
    };
    IntentFilter filter = new IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED);
    if (Build.VERSION.SDK_INT >= 33) {
      context.registerReceiver(bondReceiver, filter, Context.RECEIVER_EXPORTED);
    } else {
      context.registerReceiver(bondReceiver, filter);
    }
  }

  @Override
  public void onCancel(Object arguments) {
    sink = null;
    unregisterBondReceiver();
  }

  private void unregisterBondReceiver() {
    if (bondReceiver != null && context != null) {
      try {
        context.unregisterReceiver(bondReceiver);
      } catch (IllegalArgumentException ignored) {
        // not registered
      }
    }
    bondReceiver = null;
  }
}
