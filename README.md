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

#### Secrets

Under `Arkavo/` create `.env`

```
PATREON_CLIENT_ID=
PATREON_CLIENT_SECRET=
```

```shell
source .env; echo "// Do not commit.\nstruct Secrets {\n    static let patreonClientId = \"${PATREON_CLIENT_ID}\"\n    static let patreonClientSecret = \"${PATREON_CLIENT_SECRET}\"\n}" > "Arkavo/Arkavo/Secrets.swift"
source .env; echo "// Do not commit.\nstruct Secrets {\n    static let patreonClientId = \"${PATREON_CLIENT_ID}\"\n    static let patreonClientSecret = \"${PATREON_CLIENT_SECRET}\"\n}" > "ArkavoCreator/ArkavoCreator/Secrets.swift"
```

Note adding `[ -f "${SRCROOT}/.env" ] && source "${SRCROOT}/.env";` to the Run Script in Build Phases may be needed.

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

### Release build

#### Arkavo

```shell
cd Arkavo
xcodebuild -scheme Arkavo -sdk macosx -configuration Release build
xcodebuild -scheme Arkavo -sdk iphoneos -configuration Release build
```

#### ArkavoCreator

```shell
cd ArkavoCreator
xcodebuild -scheme ArkavoCreator -sdk macosx -configuration Release build
xcodebuild -scheme ArkavoCreator -sdk iphoneos -configuration Release build
```