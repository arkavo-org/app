# Arkavo app
_for the Apple ecosystem_

## Prerequisites

Flatbuffers
https://github.com/google/flatbuffers

```shell
brew install flatbuffers
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

### Dependencies 

- OpenTDFKit https://github.com/arkavo-org/OpenTDFKit.git

### Format

```shell
swiftformat --swiftversion 6.0 .
```
