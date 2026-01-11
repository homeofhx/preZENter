# preZENter

![preZENter](pZtPromo.png)

A presentation utility application for Mac computers. It presents an application window or video capture device live on a separate screen.

Inspired by various video conferencing software's Share Screen feature. Influenced by [Presenter Mode](https://github.com/benjones/presenterMode) by [Ben Jones](https://github.com/benjones).

**Quick Links**: [Get the latest release](https://github.com/homeofhx/preZENter/releases/latest) | [Wiki](https://github.com/homeofhx/preZENter/wiki) | [Quick start guide](https://github.com/homeofhx/preZENter/wiki/How-to-Use-%E2%80%90-The-Basics) | [Troubleshooting](https://github.com/homeofhx/preZENter/wiki/Known-Issues-&-Limitations)

## Features

- **Selective Content Presenting.** Presents only a specific app's window or a video capture device, so your audience will focus on what you want them to see.

- **Handy Tools.** Contains tools that can be helpful for your presentation, including Presenter Timer, Screen Switcher, and menu bar shortcuts.

- **Quick Setup.** Easy to use, less to learn, so you can focus more on your presentation rather than the setup;

- **Legacy Mac OS Support.** Compatible with some older version of Mac OS, as low as 10.12 (Sierra).

## Technical Details

**Mac OS Compatibility:** **X86_64 build:** 10.12 (Sierra) to 10.14 (Mojave); **Universal 2 build:** 10.15 (Catalina) or newer.

**Frameworks Used:** [Core Graphics](https://developer.apple.com/documentation/coregraphics) (app window capturing), [AVFoundation](https://developer.apple.com/documentation/avfoundation) (external video capture devices capturing), [AppKit](https://developer.apple.com/documentation/appkit) ([Cocoa](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaFundamentals/WhatIsCocoa/WhatIsCocoa.html) for the UI)

**Build Environment:** **X86_64 build:** Xcode 10. **Universal 2 build:** latest Xcode with `Deployment Target=10.15` and `Architecture=$(ARCHS_STANDARD)` (Apple Silicon, Intel).

**Beta Version:** Download this repository, then build and run the project.

> Please Note:
> 1. Beta versions can contain unimplemented functionalities, more issues, and unpredictable behaviors;
> 2. When building on Xcode 10, make sure to comment out the part indicated by the comments in the code. Otherwise Xcode can't build the project.

## Thanks

[@benjones](https://github.com/benjones) for suggesting the approach for capturing app windows and the idea of menu bar shortcuts.