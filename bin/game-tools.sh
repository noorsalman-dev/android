#!/bin/sh
# Copyright 2000-2024 JetBrains s.r.o. and contributors. Use of this source code is governed by the Apache 2.0 license.

# ---------------------------------------------------------------------
# Android Studio Game Tools startup script.
# ---------------------------------------------------------------------

message()
{
  TITLE="Cannot start Android Studio Game Tools"
  if [ -n "$(command -v zenity)" ]; then
    zenity --error --title="$TITLE" --text="$1" --no-wrap
  elif [ -n "$(command -v kdialog)" ]; then
    kdialog --error "$1" --title "$TITLE"
  elif [ -n "$(command -v notify-send)" ]; then
    notify-send "ERROR: $TITLE" "$1"
  elif [ -n "$(command -v xmessage)" ]; then
    xmessage -center "ERROR: $TITLE: $1"
  else
    printf "ERROR: %s\n%s\n" "$TITLE" "$1"
  fi
}

if [ -z "$(command -v uname)" ] || [ -z "$(command -v realpath)" ] || [ -z "$(command -v dirname)" ] || [ -z "$(command -v cat)" ] || \
   [ -z "$(command -v grep)" ]; then
  TOOLS_MSG="Required tools are missing:"
  for tool in uname realpath grep dirname cat ; do
     test -z "$(command -v $tool)" && TOOLS_MSG="$TOOLS_MSG $tool"
  done
  message "$TOOLS_MSG (SHELL=$SHELL PATH=$PATH)"
  exit 1
fi

# shellcheck disable=SC2034
GREP_OPTIONS=''
OS_TYPE=$(uname -s)
OS_ARCH=$(uname -m)

# ---------------------------------------------------------------------
# Ensure $IDE_HOME points to the directory where the IDE is installed.
# ---------------------------------------------------------------------
IDE_BIN_HOME=$(dirname "$(realpath "$0")")
IDE_HOME=$(dirname "${IDE_BIN_HOME}")
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"

# ---------------------------------------------------------------------
# Locate a JRE installation directory command -v will be used to run the IDE.
# Try (in order): $STUDIO_JDK, .../studio.jdk, .../jbr, $JDK_HOME, $JAVA_HOME, "java" in $PATH.
# ---------------------------------------------------------------------
JRE=""

# shellcheck disable=SC2154
if [ -n "$STUDIO_JDK" ] && [ -x "$STUDIO_JDK/bin/java" ]; then
  JRE="$STUDIO_JDK"
fi

if [ -z "$JRE" ] && [ -s "${CONFIG_HOME}/Google/AndroidGameDevelopmentTools/studio.jdk" ]; then
  USER_JRE=$(cat "${CONFIG_HOME}/Google/AndroidGameDevelopmentTools/studio.jdk")
  if [ -x "$USER_JRE/bin/java" ]; then
    JRE="$USER_JRE"
  fi
fi

if [ -z "$JRE" ] && [ "$OS_TYPE" = "Linux" ] && [ -f "$IDE_HOME/jbr/release" ]; then
  JBR_ARCH="OS_ARCH=\"$OS_ARCH\""
  if grep -q -e "$JBR_ARCH" "$IDE_HOME/jbr/release" ; then
    JRE="$IDE_HOME/jbr"
  fi
fi

# shellcheck disable=SC2153
if [ -z "$JRE" ]; then
  if [ -n "$JDK_HOME" ] && [ -x "$JDK_HOME/bin/java" ]; then
    JRE="$JDK_HOME"
  elif [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    JRE="$JAVA_HOME"
  fi
fi

if [ -z "$JRE" ]; then
  JAVA_BIN=$(command -v java)
else
  JAVA_BIN="$JRE/bin/java"
fi

if [ -z "$JAVA_BIN" ] || [ ! -x "$JAVA_BIN" ]; then
  message "No JRE found. Please make sure \$STUDIO_JDK, \$JDK_HOME, or \$JAVA_HOME point to valid JRE installation."
  exit 1
fi

# ---------------------------------------------------------------------
# Collect JVM options and IDE properties.
# ---------------------------------------------------------------------
IDE_PROPERTIES_PROPERTY=""
# shellcheck disable=SC2154
if [ -n "$STUDIO_PROPERTIES" ]; then
  IDE_PROPERTIES_PROPERTY="-Didea.properties.file=$STUDIO_PROPERTIES"
fi

# shellcheck disable=SC2034
IDE_CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/Google/AndroidGameDevelopmentTools"

# <IDE_HOME>/bin/[<os>/]<bin_name>.vmoptions ...
VM_OPTIONS_FILE=""
if [ -r "${IDE_BIN_HOME}/studio64.vmoptions" ]; then
  VM_OPTIONS_FILE="${IDE_BIN_HOME}/studio64.vmoptions"
else
  test "${OS_TYPE}" = "Darwin" && OS_SPECIFIC="mac" || OS_SPECIFIC="linux"
  if [ -r "${IDE_BIN_HOME}/${OS_SPECIFIC}/studio64.vmoptions" ]; then
    VM_OPTIONS_FILE="${IDE_BIN_HOME}/${OS_SPECIFIC}/studio64.vmoptions"
  fi
fi

# ... [+ $<IDE_NAME>_VM_OPTIONS || <IDE_HOME>.vmoptions (Toolbox) || <config_directory>/<bin_name>.vmoptions]
USER_VM_OPTIONS_FILE=""
if [ -n "$STUDIO_VM_OPTIONS" ] && [ -r "$STUDIO_VM_OPTIONS" ]; then
  USER_VM_OPTIONS_FILE="$STUDIO_VM_OPTIONS"
elif [ -r "${IDE_HOME}.vmoptions" ]; then
  USER_VM_OPTIONS_FILE="${IDE_HOME}.vmoptions"
elif [ -r "${CONFIG_HOME}/Google/AndroidGameDevelopmentTools/studio64.vmoptions" ]; then
  USER_VM_OPTIONS_FILE="${CONFIG_HOME}/Google/AndroidGameDevelopmentTools/studio64.vmoptions"
fi

VM_OPTIONS=""
if [ -z "$VM_OPTIONS_FILE" ] && [ -z "$USER_VM_OPTIONS_FILE" ]; then
  message "Cannot find a VM options file"
elif [ -z "$USER_VM_OPTIONS_FILE" ]; then
  VM_OPTIONS=$(grep -E -v -e "^#.*" "$VM_OPTIONS_FILE")
elif [ -z "$VM_OPTIONS_FILE" ]; then
  VM_OPTIONS=$(grep -E -v -e "^#.*" "$USER_VM_OPTIONS_FILE")
else
  VM_FILTER=""
  if grep -E -q -e "-XX:\+.*GC" "$USER_VM_OPTIONS_FILE" ; then
    VM_FILTER="-XX:\+.*GC|"
  fi
  if grep -E -q -e "-XX:InitialRAMPercentage=" "$USER_VM_OPTIONS_FILE" ; then
    VM_FILTER="${VM_FILTER}-Xms|"
  fi
  if grep -E -q -e "-XX:(Max|Min)RAMPercentage=" "$USER_VM_OPTIONS_FILE" ; then
    VM_FILTER="${VM_FILTER}-Xmx|"
  fi
  if [ -z "$VM_FILTER" ]; then
    VM_OPTIONS=$(cat "$VM_OPTIONS_FILE" "$USER_VM_OPTIONS_FILE" 2> /dev/null | grep -E -v -e "^#.*")
  else
    VM_OPTIONS=$({ grep -E -v -e "(${VM_FILTER%'|'})" "$VM_OPTIONS_FILE"; cat "$USER_VM_OPTIONS_FILE"; } 2> /dev/null | grep -E -v -e "^#.*")
  fi
fi

CLASS_PATH="$IDE_HOME/lib/platform-loader.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/util-8.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/app.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/util.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/app-backend.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/annotations.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/eclipse.lsp4j.debug.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/eclipse.lsp4j.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/eclipse.lsp4j.jsonrpc.debug.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/eclipse.lsp4j.jsonrpc.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/external-system-rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/externalProcess-rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.andel.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.bifurcan.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.fastutil.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.kernel.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.multiplatform.shims.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.reporting.api.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.reporting.shared.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.rhizomedb.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.rhizomedb.transactor.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.rhizomedb.transactor.rebase.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.rpc.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.rpc.server.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.util.codepoints.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.util.core.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.util.logging.api.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/fleet.util.serialization.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/forms_rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/groovy.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/idea_rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij-test-discovery.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.aalto.xml.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.asm.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.asm.tools.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.automaton.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.batik.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.blockmap.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.bouncy.castle.pgp.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.bouncy.castle.provider.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.caffeine.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.cglib.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.classgraph.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.cli.parser.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.commons.cli.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.commons.codec.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.commons.compress.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.commons.imaging.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.commons.io.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.commons.lang3.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.commons.logging.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.fastutil.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.gson.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.guava.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.hash4j.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.hdr.histogram.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.http.client.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.icu4j.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.imgscalr.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.ini4j.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.ion.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jackson.databind.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jackson.dataformat.yaml.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jackson.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jackson.jr.objects.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jackson.module.kotlin.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.java.websocket.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.javax.annotation.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jaxen.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jbr.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jcef.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jcip.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jediterm.core.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jediterm.ui.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jettison.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jgoodies.common.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jgoodies.forms.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jsonpath.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jsoup.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jsvg.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jvm.native.trusted.roots.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.jzlib.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kotlin.reflect.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kotlinx.collections.immutable.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kotlinx.coroutines.core.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kotlinx.coroutines.debug.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kotlinx.coroutines.slf4j.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kotlinx.datetime.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kotlinx.html.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kotlinx.io.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kotlinx.serialization.cbor.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kotlinx.serialization.core.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kotlinx.serialization.json.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kotlinx.serialization.protobuf.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.kryo5.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.ktor.client.cio.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.ktor.client.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.ktor.io.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.ktor.network.tls.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.ktor.server.cio.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.ktor.utils.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.lz4.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.markdown.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.miglayout.swing.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.mvstore.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.netty.buffer.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.netty.codec.compression.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.netty.codec.http.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.netty.handler.proxy.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.opentelemetry.exporter.sender.jdk.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.opentelemetry.sdk.autoconfigure.spi.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.oro.matcher.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.protobuf.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.proxy.vole.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.pty4j.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.rd.core.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.rd.framework.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.rd.swing.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.rd.text.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.rhino.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.snakeyaml.engine.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.snakeyaml.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.sshj.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.stream.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.swingx.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.velocity.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.winp.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.xerces.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.xstream.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.xtext.xbase.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.libraries.xz.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.analysis.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.analysis.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.builtInServer.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.builtInServer.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.core.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.core.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.core.ui.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.credentialStore.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.credentialStore.ui.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.debugger.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.debugger.impl.rpc.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.debugger.impl.shared.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.debugger.impl.ui.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.debugger.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.diff.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.diff.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.duplicates.analysis.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.eel.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.externalProcessAuthHelper.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.externalSystem.dependencyUpdater.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.externalSystem.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.externalSystem.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.find.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.ide.concurrency.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.ide.core.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.ide.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.ide.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.kernel.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.lang.core.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.lang.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.lang.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.locking.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.lsp.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.lsp.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.managed.cache.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.polySymbols.backend.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.polySymbols.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.projectFrame.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.projectModel.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.projectModel.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.rpc.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.rpc.topics.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.scopes.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.smRunner.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.util.ex.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.util.ui.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.vcs.core.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.vcs.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.vcs.shared.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.welcomeScreen.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.platform.welcomeScreen.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.regexp.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.xml.analysis.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.xml.analysis.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.xml.dom.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.xml.dom.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.xml.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.xml.parser.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.xml.psi.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.xml.psi.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.xml.structureView.impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.xml.structureView.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.xml.syntax.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/intellij.xml.ui.common.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/javax.activation.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/javax.annotation-api.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/jaxb-api.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/jaxb-runtime.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/jps-model.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/junit4.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/kotlinx-coroutines-guava.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/lib.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/opentelemetry.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/rd-gen.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/resources.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/stats.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/trove.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/lib/util_rt.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/plugins/android/lib/*"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/plugins/android/resources/*"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/plugins/java/lib/java-api.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/plugins/java/lib/java-frontback.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/plugins/java/lib/java-impl.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/plugins/java/lib/resources.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/plugins/java/lib/java_resources_en.jar"
CLASS_PATH="$CLASS_PATH:$IDE_HOME/plugins/java/lib/modules/*"

# ---------------------------------------------------------------------
# Run the IDE.
# ---------------------------------------------------------------------
IFS="$(printf '\n\t')"
# shellcheck disable=SC2086
exec "$JAVA_BIN" \
  -classpath "$CLASS_PATH" \
  "-XX:ErrorFile=$HOME/java_error_in_studio_%p.log" \
  "-XX:HeapDumpPath=$HOME/java_error_in_studio_.hprof" \
  ${VM_OPTIONS} \
  "-Djb.vmOptionsFile=${USER_VM_OPTIONS_FILE:-${VM_OPTIONS_FILE}}" \
  ${IDE_PROPERTIES_PROPERTY} \
  "-Xbootclasspath/a:$IDE_HOME/lib/nio-fs.jar" -Djava.system.class.loader=com.intellij.util.lang.PathClassLoader -Didea.vendor.name=Google -Didea.paths.selector=AndroidStudio2026.1.4 "-Djna.boot.library.path=$IDE_HOME/lib/jna/amd64" -Djna.nosys=true -Djna.noclasspath=true "-Dpty4j.preferred.native.folder=$IDE_HOME/lib/pty4j" -Dio.netty.allocator.type=pooled "-Dskiko.library.path=$IDE_HOME/lib/skiko-awt-runtime-all" "-Dintellij.platform.runtime.repository.path=$IDE_HOME/modules/module-descriptors.dat" -Didea.platform.prefix=AndroidStudio -XX:FlightRecorderOptions=stackdepth=256 --add-opens=java.base/sun.net.www.protocol.https=ALL-UNNAMED -Dij.startup.error.handler.class=com.intellij.platform.ide.bootstrap.StudioStartupErrorHandler -XX:CompileCommand=exclude,org.jetbrains.kotlin.serialization.deserialization.TypeDeserializer::simpleType -XX:CompileCommand=exclude,org.jetbrains.kotlin.serialization.deserialization.TypeDeserializer::toAttributes -Dsplash=true -Daether.connector.resumeDownloads=false -Dcompose.swing.render.on.graphics=true --enable-native-access=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.ref=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/java.nio.charset=ALL-UNNAMED --add-opens=java.base/java.text=ALL-UNNAMED --add-opens=java.base/java.time=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.util.concurrent=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.locks=ALL-UNNAMED --add-opens=java.base/jdk.internal.ref=ALL-UNNAMED --add-opens=java.base/jdk.internal.vm=ALL-UNNAMED --add-opens=java.base/sun.net.dns=ALL-UNNAMED --add-opens=java.base/sun.nio=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.base/sun.nio.fs=ALL-UNNAMED --add-opens=java.base/sun.security.ssl=ALL-UNNAMED --add-opens=java.base/sun.security.util=ALL-UNNAMED --add-opens=java.desktop/com.sun.java.swing=ALL-UNNAMED --add-opens=java.desktop/com.sun.java.swing.plaf.gtk=ALL-UNNAMED --add-opens=java.desktop/java.awt=ALL-UNNAMED --add-opens=java.desktop/java.awt.dnd.peer=ALL-UNNAMED --add-opens=java.desktop/java.awt.event=ALL-UNNAMED --add-opens=java.desktop/java.awt.font=ALL-UNNAMED --add-opens=java.desktop/java.awt.image=ALL-UNNAMED --add-opens=java.desktop/java.awt.peer=ALL-UNNAMED --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.desktop/javax.swing.plaf.basic=ALL-UNNAMED --add-opens=java.desktop/javax.swing.text=ALL-UNNAMED --add-opens=java.desktop/javax.swing.text.html=ALL-UNNAMED --add-opens=java.desktop/javax.swing.text.html.parser=ALL-UNNAMED --add-opens=java.desktop/sun.awt=ALL-UNNAMED --add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED --add-opens=java.desktop/sun.awt.datatransfer=ALL-UNNAMED --add-opens=java.desktop/sun.awt.image=ALL-UNNAMED --add-opens=java.desktop/sun.font=ALL-UNNAMED --add-opens=java.desktop/sun.java2d=ALL-UNNAMED --add-opens=java.desktop/sun.swing=ALL-UNNAMED --add-opens=java.management/sun.management=ALL-UNNAMED --add-opens=jdk.attach/sun.tools.attach=ALL-UNNAMED --add-opens=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-opens=jdk.internal.jvmstat/sun.jvmstat.monitor=ALL-UNNAMED --add-opens=jdk.jdi/com.sun.tools.jdi=ALL-UNNAMED -Didea.load.plugins=false -Dprofiler.task.based.ux=false -Didea.platform.prefix=AndroidGameDevelopmentTools -Didea.initially.ask.config=never \
  com.android.tools.idea.MainWrapper \
  "$@"
