FROM mongo:8.0

# Railway's free/trial volume is 500 MB, while MongoDB reserves 500 MB of
# free space before starting an index build. Keep a smaller safety margin so
# Jac can create its authentication indexes on the hackathon deployment.
CMD ["mongod", "--setParameter", "indexBuildMinAvailableDiskSpaceMB=50"]
