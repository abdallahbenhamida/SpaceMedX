/// One slot of a measurement ring buffer (`[dataRecord, flag]` in e77hal.js).
class RingEntry {
  RingEntry(this.record, this.flag);

  /// The measurement record, or an empty map for a deleted slot (`{}`).
  final Map<String, Object?> record;
  final bool flag;
}

/// Port of `dataRingBuffer(length)` from e77hal.js, including its quirks:
/// `prev()` does not wrap below 0 (JavaScript's `(-1) % n` is `-1`, which
/// addresses no slot).
class DataRingBuffer {
  DataRingBuffer(this.length) : _buffer = List<RingEntry?>.filled(length, null);

  final int length;
  final List<RingEntry?> _buffer;
  int _pointer = 0;

  int getptr() => _pointer;

  void setptr(int pointer) => _pointer = pointer;

  /// `get(key)`: negative keys are relative to the pointer.
  RingEntry? get(int key) {
    final i = key < 0 ? _pointer + key : key;
    if (i < 0 || i >= length) return null;
    return _buffer[i];
  }

  RingEntry push(RingEntry item) {
    _buffer[_pointer] = item;
    _pointer = (_pointer + 1) % length;
    return item;
  }

  RingEntry? prev() {
    final tmp = _pointer - 1;
    if (tmp < 0) return null; // JS: (0 - 1) % length === -1 -> undefined
    final entry = _buffer[tmp];
    if (entry != null) {
      _pointer = tmp;
      return entry;
    }
    return null;
  }

  RingEntry? next() {
    if (_buffer[_pointer] != null) {
      _pointer = (_pointer + 1) % length;
      return _buffer[_pointer];
    }
    return null;
  }
}
