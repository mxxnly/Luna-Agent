package main

import (
	"flag"
	"log"
	"net/http"

	"github.com/mxxnly/Luna-Agent/internal/mockctrl"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:18080", "listen address")
	code := flag.String("enroll-code", "test-enroll", "valid enroll code")
	flag.Parse()
	s, err := mockctrl.New(*code)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("mockcontrol on http://%s", *addr)
	log.Fatal(http.ListenAndServe(*addr, s.Handler()))
}
