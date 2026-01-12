cc_library(
    name = "shim",
    srcs = ["shim.cc"],
    hdrs = ["shim.h"],
    deps = ["@google_cloud_cpp//:experimental-storage_grpc"],
)

cc_shared_library(
    name = "shim_shared",
    deps = [":shim"],
)
