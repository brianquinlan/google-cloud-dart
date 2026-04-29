# Python Protobuf JSON Verifier

This tool helps validate the JSON serialization behavior of Protobuf messages against the official Python/C++ implementation.

## Setup

brew install protobuf

1.  Create a virtual environment (recommended):
    ```bash
    python3 -m venv venv
    source venv/bin/activate
    ```

2.  Install dependencies:
    ```bash
    pip install -r requirements.txt
    ```

## Usage

Run the verification script:
```bash
python verify.py
```

## Testing Custom Messages

To test messages like `TestAllTypesProto3`:

1.  Download the proto file:
    ```bash
    curl -O https://raw.githubusercontent.com/protocolbuffers/protobuf/main/src/google/protobuf/test_messages_proto3.proto
    ```

2.  Compile it:
    ```bash
    protoc --python_out=. test_messages_proto3.proto
    ```

3.  Uncomment the relevant lines in `verify.py` to use it.
