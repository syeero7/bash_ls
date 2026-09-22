package protocol

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
)

const headerField = "Content-Length: "
const fieldSeparator = "\r\n\r\n"

func Decode[T any](data []byte) (*T, error) {
	header, content, ok := bytes.Cut(data, []byte(fieldSeparator))
	if !ok {
		return nil, errors.New("separator not found")
	}

	lengthBytes := header[len(headerField):]
	contentLength, err := strconv.Atoi(string(lengthBytes))
	if err != nil {
		return nil, err

	}

	if len(content) < contentLength {
		return nil, fmt.Errorf("required content length: %d current: %d", len(content), contentLength)
	}

	var message T
	err = json.Unmarshal(content[:contentLength], &message)
	return &message, err
}

func Encode(content any) ([]byte, error) {
	data, err := json.Marshal(content)
	if err != nil {
		return nil, err
	}

	msg := []byte(headerField + strconv.Itoa(len(data)) + fieldSeparator + string(data))
	return msg, nil
}

func Split(data []byte, _ bool) (advance int, token []byte, err error) {
	header, content, ok := bytes.Cut(data, []byte(fieldSeparator))
	if !ok {
		return 0, nil, nil
	}

	lengthBytes := header[len(headerField):]
	length, err := strconv.Atoi(string(lengthBytes))
	if err != nil {
		return 0, nil, err

	}

	if len(content) < length {
		return 0, nil, nil
	}

	total := len(headerField) + len(lengthBytes) + len(fieldSeparator) + length
	return total, data[:total], nil
}
