"""Source register: URLs are discovery entry points, not assertions of access."""
from dataclasses import dataclass, asdict

@dataclass(frozen=True)
class Dataset:
    id: str
    name: str
    agency: str
    url: str
    description: str
    adapter: str
    access: str = "VERIFY_PER_ASSET"

DATASETS = (
    Dataset("NASA_OSDR", "NASA Open Science Data Repository", "NASA", "https://osdr.nasa.gov/", "Space biology and biomedical investigations", "catalog"),
    Dataset("NASA_PSI", "NASA Physical Sciences Informatics", "NASA", "https://psi.nasa.gov/", "Physical sciences and biophysics investigations", "catalog"),
    Dataset("NASA_LSDA", "NASA Life Sciences Data Archive", "NASA", "https://nlsp.nasa.gov/", "Human spaceflight and analog physiology", "catalog"),
    Dataset("NASA_UTMB_BEDREST", "NASA UTMB Bed-Rest Campaigns", "NASA", "https://nlsp.nasa.gov/", "Human bed-rest physiology", "catalog"),
    Dataset("NASA_EDA", "NASA Environmental Data App", "NASA", "https://visualization.osdr.nasa.gov/eda/", "Cabin environment and radiation context", "catalog"),
    Dataset("NASA_RADLAB", "NASA RadLab", "NASA", "https://visualization.osdr.nasa.gov/", "Radiation dosimetry", "catalog"),
    Dataset("ESA_HREDA", "ESA Human Research Data Archive", "ESA", "https://hredaint.esac.esa.int/hreda/", "Human research investigations", "catalog"),
    Dataset("ESA_BRACE_2023", "ESA BRACE 2023", "ESA", "https://doi.org/10.57780/esa-3nbdkc9", "Bed-rest and artificial-gravity research", "catalog"),
    Dataset("ESA_CAROT", "ESA CAROT", "ESA", "https://doi.org/10.57780/esa-g3lxiiq", "Cardiovascular deconditioning research", "catalog"),
    Dataset("PHYSIONET", "PhysioNet", "PhysioNet", "https://physionet.org/", "Physiological reference repository", "catalog"),
    Dataset("BIDMC", "BIDMC PPG and Respiration", "PhysioNet", "https://physionet.org/content/bidmc/1.0.0/", "PPG, ECG, respiration and numeric signals", "bidmc_csv", "OPEN_WITH_ATTRIBUTION"),
    Dataset("SLEEP_EDFX", "Sleep-EDF Expanded", "PhysioNet", "https://physionet.org/content/sleep-edfx/1.0.0/", "Polysomnography and sleep annotations", "asset_manifest", "OPEN_WITH_ATTRIBUTION"),
    Dataset("CAP_SLEEP", "CAP Sleep Database", "PhysioNet", "https://physionet.org/content/capslpdb/1.0.0/", "Multichannel sleep recordings", "asset_manifest", "OPEN_WITH_ATTRIBUTION"),
)

def list_datasets():
    return [asdict(d) for d in DATASETS]

def get_dataset(dataset_id: str) -> Dataset:
    for d in DATASETS:
        if d.id == dataset_id.upper():
            return d
    raise KeyError(dataset_id)
