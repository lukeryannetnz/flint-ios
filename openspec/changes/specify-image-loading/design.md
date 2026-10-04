# Design: Load and import images without freezing the screen

## Context

Flint currently reads some image files while laying out notes and opening or updating the fullscreen viewer. Large images can also consume far more memory than their on-screen size needs. Reading and preparing them should happen in the background with clear limits.

## Goals / Non-Goals

The goal is to answer: **Can large or unavailable images load and import without freezing the screen, losing text or using unbounded memory?** This part defines the proposed behavior and its tests. Other PRs cover the remaining parts of the plan; the app has not been changed by these specs.

## Decisions

1. Use Image I/O, Apple’s image-reading framework, to make smaller display images directly from source files. Views receive prepared images rather than opening files themselves.
2. Keep reusable images by vault/resource identity, file version and requested size, and give note/viewer/import requests identities so old results can be ignored. The 32 MiB cache limit is not a limit on total process memory.
3. Move temporary picker copies and camera encoding into background work. Prepare/encode one import at a time, using the same image-processing slot as display decoding; limit photo/camera preparations to 4096 pixels, encode to files, and stream Files copies without decoding or changing their source bytes. Release picker inputs promptly and measure their temporary memory separately. Keep source/destination permissions and finish importing the asset before adding its markdown reference.

## Risks / Trade-offs

The limits are proposed acceptance criteria, not measurements of the current app. Some iOS or Dropbox information may be unavailable; logs and test records must state what is missing. Notes and images retain their current file formats.
