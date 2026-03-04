from himawari_hsd2nc import convert_ahi


if __name__ == "__main__":
    convert_ahi(
        input_file="data/HS_H09_YYYYMMDD_HHMM_B01_FLDK_R10_S0110.DAT.bz2",
        output_nc="output/example_bbox.nc",
        bands=[1],
        roi=(110.0, 15.0, 130.0, 35.0),
    )
