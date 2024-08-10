# Arkavo app
_for the Apple ecosystem_

## Design

### Entity

```mermaid
graph TD
  A[Account] --> B[Content]
  B --> C[Metadata]
  A --> D[Profile]
  D --> E[Thought]
  E --> F[Media]
  E --> G[Text]
  A --> H[SecureStream]
  H --> I[ThoughtStreamView]
```

## Development

### Dependencies 

- OpenTDFKit https://github.com/arkavo-org/OpenTDFKit.git

### Format

```shell
swiftformat --swiftversion 6.0 .
```
