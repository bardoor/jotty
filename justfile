default: build

build:
    native/aec/build.sh
    swift build -c release --package-path native/recorder
    cp native/aec/.build/libJottyAEC.dylib native/recorder/.build/release/libJottyAEC.dylib
    mix deps.get
    mix escript.build
