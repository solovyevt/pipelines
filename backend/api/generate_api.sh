# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# !/bin/sh

# This file generates API sources from the protocol buffers defined in this
# directory using Bazel, then copies them back into the source tree so they can
# be checked-in.

set -ex

BAZEL_BINDIR=$(bazel info bazel-bin)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null && pwd)"
SWAGGER_CMD=${DIR}/../../bazel-bin/external/com_github_go_swagger/cmd/swagger/*stripped/swagger
AUTOGEN_CMD="${DIR}/../../bazel-bin/external/com_github_mbrukman_autogen/autogen_tool"
GENERATED_GO_PROTO_FILES="${BAZEL_BINDIR}/backend/api/api_generated_go_sources/src/github.com/kubeflow/pipelines/backend/api/go_client/*.go"

# TODO this script should be able to be run from anywhere, not just within .../backend/api/

# Delete currently generated code.
rm -r -f go_http_client/*
rm -r -f go_client/*

# Build required tools.
bazel build @com_github_mbrukman_autogen//:autogen_tool
bazel build @com_github_go_swagger//cmd/swagger

# Build .pb.go and .gw.pb.go files from the proto sources.
bazel build //backend/api:api_generated_go_sources

set -x
# Copy the generated files into the source tree and add license.
for f in $GENERATED_GO_PROTO_FILES; do
  target=${DIR}/go_client/$(basename ${f})
  cp $f $target
  chmod 766 $target
  ${AUTOGEN_CMD} -i --no-tlc -c "Google LLC" -l apache $target
done

# Generate and copy back into source tree .swagger.json files.
bazel build //backend/api:api_swagger
cp ${BAZEL_BINDIR}/backend/api/*.swagger.json swagger

jq -s '
    reduce .[] as $item ({}; . * $item) |
    .info.title = "Kubeflow Pipelines API" |
    .info.description = "This file contains REST API specification for Kubeflow Pipelines. The file is autogenerated from the swagger definition." |
    .info.version = "0.1.20"
' ${DIR}/swagger/{run,job,pipeline,experiment,pipeline.upload}.swagger.json > "${DIR}/swagger/kfp_api_single_file.swagger.json"

# Generate Go HTTP client from the swagger files.
${SWAGGER_CMD} generate client \
  -f ${DIR}/swagger/job.swagger.json \
  -A job \
  --principal models.Principal \
  -c job_client \
  -m job_model \
  -t go_http_client

${SWAGGER_CMD} generate client \
  -f ${DIR}/swagger/run.swagger.json \
  -A run \
  --principal models.Principal \
  -c run_client \
  -m run_model \
  -t go_http_client

${SWAGGER_CMD} generate client \
  -f ${DIR}/swagger/experiment.swagger.json \
  -A experiment \
  --principal models.Principal \
  -c experiment_client \
  -m experiment_model \
  -t go_http_client

${SWAGGER_CMD} generate client \
  -f ${DIR}/swagger/pipeline.upload.swagger.json \
  -A pipeline_upload \
  --principal models.Principal \
  -c pipeline_upload_client \
  -m pipeline_upload_model \
  -t go_http_client

${SWAGGER_CMD} generate client \
  -f ${DIR}/swagger/pipeline.swagger.json \
  -A pipeline \
  --principal models.Principal \
  -c pipeline_client \
  -m pipeline_model \
  -t go_http_client

${SWAGGER_CMD} generate client \
  -f ${DIR}/swagger/visualization.swagger.json \
  -A visualization \
  --principal models.Principal \
  -c visualization_client \
  -m visualization_model \
  -t go_http_client

# Hack to fix an issue with go-swagger
# See https://github.com/go-swagger/go-swagger/issues/1381 for details.
sed -i -- 's/MaxConcurrency int64 `json:"max_concurrency,omitempty"`/MaxConcurrency int64 `json:"max_concurrency,omitempty,string"`/g' ${DIR}/go_http_client/job_model/api_job.go
sed -i -- 's/IntervalSecond int64 `json:"interval_second,omitempty"`/IntervalSecond int64 `json:"interval_second,omitempty,string"`/g' ${DIR}/go_http_client/job_model/api_periodic_schedule.go
sed -i -- 's/MaxConcurrency string `json:"max_concurrency,omitempty"`/MaxConcurrency int64 `json:"max_concurrency,omitempty,string"`/g' ${DIR}/go_http_client/job_model/api_job.go
sed -i -- 's/IntervalSecond string `json:"interval_second,omitempty"`/IntervalSecond int64 `json:"interval_second,omitempty,string"`/g' ${DIR}/go_http_client/job_model/api_periodic_schedule.go

# Executes the //go:generate directives in the generated code.
go generate ./...

# Add license to files in go_http_client.
find ${DIR}/go_http_client/ -name "*.go" -exec ${AUTOGEN_CMD} -i --no-tlc -c "Google LLC" -l apache {} \;

# Finally, run gazelle to add BUILD files for the generated code.
bazel run //:gazelle
