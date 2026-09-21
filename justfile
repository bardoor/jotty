default: build

build:
    swift build -c release --package-path native/recorder
    mix deps.get
    mix escript.build
