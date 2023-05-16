package main

import (
    "fmt"
    "net/http"
    "os"
    "time"
)


func health(w http.ResponseWriter, req *http.Request) {
    fmt.Fprintf(w, "OK\n")
}


func test(w http.ResponseWriter, req *http.Request) {
    fmt.Fprintf(w, "OK\n")
}


// Create a function that calls an Http server at http://service1/test
func callHttpServer(url string) (string, error) {
    resp, err := http.Get(url)
    if err != nil {
        return "", err
    }
    defer resp.Body.Close()
    return "", nil
}


func loop(pollUrl string) {
    for {
        // Call http server at pollUrl
        _, err := callHttpServer(pollUrl)


        // Wait for 1 second
        time.Sleep(1 * time.Second)
        if err != nil {
            fmt.Println("Error calling http server")
        }
    }
}


func loopOffThread(pollUrl string) {
    go loop(pollUrl)
}


func main() {
    http.HandleFunc("/healthz", health)
    http.HandleFunc("/test", test)


    pollUrl, polling := os.LookupEnv("POLL_URL")
    if polling {
        loopOffThread(pollUrl)
    }
    http.ListenAndServe(":5000", nil)
}

