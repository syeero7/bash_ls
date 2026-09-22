package main

import (
	"bufio"
	"log"
	"os"

	"github.com/syeero7/bash_ls/protocol"
)

func main() {
	var logFile *os.File

arg_loop:
	for i, arg := range os.Args {
		switch arg {
		case "--log-file":
			if next := i + 1; next < len(os.Args) {
				var err error
				logFile, err = createLogFile(os.Args[next])
				if err != nil {
					panic(err)
				}

				break arg_loop
			}

		}
	}

	if logFile != nil {
		defer logFile.Close()
	}

	scanner := bufio.NewScanner(os.Stdin)
	scanner.Split(protocol.Split)

	for scanner.Scan() {
		msg := scanner.Text()
		log.Println(msg)

	}

	if err := scanner.Err(); err != nil {
		log.Println("scanner err: ", err)
	}

}

func createLogFile(path string) (*os.File, error) {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return nil, err
	}

	log.SetOutput(file)
	log.SetPrefix("[bash_ls] ")
	log.SetFlags(log.LstdFlags | log.Lshortfile)
	return file, nil
}
