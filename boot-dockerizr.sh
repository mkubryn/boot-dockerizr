#!/usr/bin/env bash

set -e

exit_with_usage() {
    echo -e "boot-dockerizr - prepares efficient docker image layers' structure for spring-boot applications"
    echo -e "\n  Usage: $0 -a|--app-jar [SPRING_BOOT_APP_JAR] -b|--build-root [DOCKER_BUILD_ROOT_DIR] [APP_OWN_MODULE]..."
    exit 1
}

log_info() {
    echo -e "[info] $1"
}

# Argument parsing
MODULES=""
while (( "$#" )); do
  case "$1" in
    -a|--app-jar)
      BOOT_JAR=$2; shift 2
      ;;
    -b|--build-root)
      BUILD_ROOT="$2/docker-build"; shift 2
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "[error] Unsupported flag $1" >&2
      exit_with_usage
      ;;
    *) # preserve positional arguments
      MODULES="$MODULES $1"; shift
      ;;
  esac
done
eval set -- "${MODULES}"

# Usage
if [[ -z ${BUILD_ROOT} ]] || [[ -z ${BOOT_JAR} ]]; then
    exit_with_usage
fi

log_info "Processing app: $BOOT_JAR"
log_info "Data dir: $BUILD_ROOT"

# Cleanup build root
mkdir -p ${BUILD_ROOT}
rm -rf ${BUILD_ROOT}/*

log_info "Extracting app libs (jar files) for the lib layer"
unzip -qq ${BOOT_JAR} -d ${BUILD_ROOT} "BOOT-INF/lib/*"

log_info "Extracting app classes for the classes layer"
unzip -qq ${BOOT_JAR} -d ${BUILD_ROOT} "BOOT-INF/classes/*"

mv ${BUILD_ROOT}/BOOT-INF/* ${BUILD_ROOT}/
rmdir ${BUILD_ROOT}/BOOT-INF


# Sub-module handling
mkdir ${BUILD_ROOT}/modules.tmp
for module in $@; do
    log_info "Moving app lib '$module' from jar to the classes layer"
    mkdir -p ${BUILD_ROOT}/modules.tmp
    unzip -qq ${BUILD_ROOT}/lib/${module}.jar -d ${BUILD_ROOT}/modules.tmp/${module}/
    rm ${BUILD_ROOT}/lib/${module}.jar
    rm -rf "${BUILD_ROOT}/modules.tmp/${module}/META-INF"
    cp -r ${BUILD_ROOT}/modules.tmp/${module}/* ${BUILD_ROOT}/classes/
done
rm -rf ${BUILD_ROOT}/modules.tmp


START_CLASS=$(unzip -c ${BOOT_JAR} META-INF/MANIFEST.MF | grep "Start-Class:" | cut -d ' ' -f 2 | tr -d '\r' )

echo -e "#!/usr/bin/env bash
JAVA_CP='/app/classes/:/app/lib/*:/app/*'
echo '[boot-dockerizr] Initializing application'
echo \"  OPS_JVM: \${OPS_JVM}\"
echo \"  OPS_APP: \${OPS_APP}\"
echo \"  Java classpath: \${JAVA_CP}\"
echo
java \${OPS_JVM} -cp \"\${JAVA_CP}\" ${START_CLASS} \${OPS_APP}" > ${BUILD_ROOT}/run.sh
chmod +x ${BUILD_ROOT}/run.sh

echo
log_info "Application data written to $(pwd)/${BUILD_ROOT}"
log_info "Inside your Dockerfile add (preserve the order):"
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
