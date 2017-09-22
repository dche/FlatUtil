// swift-tools-version:4.0
//
// FlatUtil - Package.swift
//
// Copyright (c) 2016 The FlatUtil authors.
// Licensed under MIT License.

import PackageDescription

let package = Package(
    name: "FlatUtil",
    products: [
        .library(
            name: "FlatUtil",
            targets: ["FlatUtil"]
        )
    ],
    targets: [
        .target(
            name: "FlatUtil",
            path: "Sources"
        ),
        .testTarget(
            name: "FlatUtilTests",
            dependencies: ["FlatUtil"],
            path: "Tests/FlatUtilTests"
        ),
    ]
)
