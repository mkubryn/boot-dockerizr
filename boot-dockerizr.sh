#!/usr/bin/env bash

set -e

if [[ $# -lt 2 ]]; then
    echo "[info] boot-dockerizr - prepares efficient docker image layers' structure for spring-boot applications"
    echo -e "[info] \n  Usage: $0 [SPRING_BOOT_APP_JAR] [BUILD_ROOT_DIR] [SUBMODULE]..."
    exit 1
fi

BOOT_JAR="$1"
BUILD_ROOT="${2}/docker-build"
shift 2

echo "[info] Processing app: $BOOT_JAR"
echo "[info] Docker build root: $BUILD_ROOT"

# Cleanup build root
mkdir -p ${BUILD_ROOT}
rm -rf ${BUILD_ROOT}/*

echo "[info] Extracting app libs (jar files) for the lib layer"
unzip -qq ${BOOT_JAR} -d ${BUILD_ROOT} "BOOT-INF/lib/*"

echo "[info] Extracting app classes for the classes layer"
unzip -qq ${BOOT_JAR} -d ${BUILD_ROOT} "BOOT-INF/classes/*"

mv ${BUILD_ROOT}/BOOT-INF/* ${BUILD_ROOT}/
rmdir ${BUILD_ROOT}/BOOT-INF


# Sub-module handling
mkdir ${BUILD_ROOT}/modules.tmp
for module in $@; do
    echo "[info] Moving app lib '$module' from jar to the classes layer"
    mkdir -p ${BUILD_ROOT}/modules.tmp
    unzip -qq ${BUILD_ROOT}/lib/${module}.jar -d ${BUILD_ROOT}/modules.tmp/${module}/
    rm ${BUILD_ROOT}/lib/${module}.jar
    rm -rf "${BUILD_ROOT}/modules.tmp/${module}/META-INF"
    cp -r ${BUILD_ROOT}/modules.tmp/${module}/* ${BUILD_ROOT}/classes/
done
rm -rf ${BUILD_ROOT}/modules.tmp


START_CLASS=$(unzip -c ${BOOT_JAR} META-INF/MANIFEST.MF | grep "Start-Class:" | cut -d ' ' -f 2 | tr -d '\r' )

echo -e "[info] #!/usr/bin/env bash
JAVA_CP='/app/classes/:/app/lib/*:/app/*'
echo '[boot-dockerizr] Initializing application'
echo \"  OPS_JVM: \${OPS_JVM}\"
echo \"  OPS_APP: \${OPS_APP}\"
echo \"  Java classpath: \${JAVA_CP}\"
echo
java \${OPS_JVM} -cp \"\${JAVA_CP}\" ${START_CLASS} \${OPS_APP}" > ${BUILD_ROOT}/run.sh
chmod +x ${BUILD_ROOT}/run.sh

echo
echo "[info] Application data written to $(pwd)/${BUILD_ROOT}"
echo "[info] Inside your Dockerfile add (preserve the order):"
echo -e "
# Application layers
ADD docker-build/run.sh /app/
ADD docker-build/lib /app/lib
ADD docker-build/classes /app/classes
# JVM parameters
ENV OPS_JVM=''
# Application parameters
ENV OPS_APP=''
# Application run command
CMD '/app/run.sh'"
