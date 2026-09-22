package protocol_test

import (
	"testing"

	"github.com/syeero7/bash_ls/protocol"
)

func TestEncode(t *testing.T) {
	msg := struct {
		Test bool `json:"test"`
	}{Test: true}

	result, err := protocol.Encode(msg)
	if err != nil {
		t.Errorf("Encode() failed: %v", err)
	}

	const expected = "Content-Length: 13\r\n\r\n" + `{"test":true}`
	if string(result) != expected {
		t.Errorf("Encode() expected: %s got: %s", expected, result)
	}
}

func TestDecode(t *testing.T) {
	type testMsg struct {
		Test bool `json:"test"`
	}

	var msg = []byte("Content-Length: 13\r\n\r\n" + `{"test":true}`)

	result, err := protocol.Decode[testMsg](msg)
	if err != nil {
		t.Errorf("Decode() failed: %v", err)
	}

	const expected = "Content-Length: 13\r\n\r\n" + `{"test":true}`
	if result.Test != true {
		t.Errorf("Decode() expected: true got: %v", result.Test)
	}
}
