# Arkavo app
_for the Apple ecosystem_

## Prerequisites

Flatbuffers
https://github.com/google/flatbuffers

```shell
brew install flatbuffers
```

Apple Pkl
https://pkl-lang.org
https://pkl-lang.org/swift/current/quickstart.html

```shell
curl -L https://github.com/apple/pkl-swift/releases/download/0.2.1/pkl-gen-swift-macos.bin -o pkl-gen-swift
chmod +x pkl-gen-swift
```

## Design

### Entity

- Account
- Profile
- Stream
- Content
- Thought

## Development

### Initialize

#### Flatbuffers (if changed)

Events

```shell
flatc --binary --swift -o Arkavo/Arkavo idl/event.fbs
cd Arkavo/Arkavo
mv event_generated.swift EventServiceModel.swift
```

Entities

```shell
flatc --binary --swift -o Arkavo/Arkavo idl/entity.fbs
cd Arkavo/Arkavo
mv entity_generated.swift EntityServiceModel.swift
```

Metadata

```shell
flatc --binary --swift -o Arkavo/Arkavo idl/metadata.fbs
cd Arkavo/Arkavo
mv metadata_generated.swift MetadataServiceModel.swift
```

#### Pkl (if changed)

```shell
./pkl-gen-swift pkl/Topics.pkl -o Arkavo/Arkavo/
```

### Dependencies 

- OpenTDFKit https://github.com/arkavo-org/OpenTDFKit.git

### Format

```shell
swiftformat --swiftversion 6.0 .
```
