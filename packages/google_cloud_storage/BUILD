load("@rules_cc//cc:defs.bzl", "cc_library", "cc_shared_library")

cc_library(
    name = "shim",
    srcs = ["shim.cc"],
    hdrs = ["shim.h"],
    deps = ["@google_cloud_cpp//:storage"],
)

cc_shared_library(
    name = "shim_shared",
    deps = [":shim"],
)
