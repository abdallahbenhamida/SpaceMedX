from .processing.database import Store

def main():
    Store().create_schema()
    print("SpaceMedx foundation tables created (development bootstrap)")

if __name__ == "__main__": main()
