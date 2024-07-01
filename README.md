[![progress-banner](https://backend.codecrafters.io/progress/http-server/dd95bd37-a3b1-4058-b29b-60ff03d2949d)](https://app.codecrafters.io/users/codecrafters-bot?r=2qF)

# Noob Http Server

This is not like prod-ready server or anything. The purpose of this project was to learn the internal mechanism of how a typical HTTP server works. Here I have built a simple server for `HTTP/1.1` protocol.

### 📖 Learnings

Following are the things which I learned:

* Establishing connection via TCP server. 
* Reading the client request.
* Parsing the client request (Request line, Headers & Body).
* Forming the response (Status line, Headers & Body).
* Sending the response back to the client.
* Handling multiple clients (i.e., concurrent connections)
* Handling signal sent from terminal running the server.
* Sending over the file to client upon request.
* Learn some bits about HTTP compression mechanism.
* Parsing for the multiple compression schemes.
* Support for Gzip compression.

### ⚡️ Requirements

The project is written in [Zig](https://ziglang.org/) programming language. The experience to use this language was pleasant. I would encourage for people to try it out. The comunity of the language although relatively small, has been a helping one. I would continue doing some other projects on this language.

<a href="https://emoji.gg/emoji/3421-zig"><img src="https://cdn3.emoji.gg/emojis/3421-zig.png" width="64px" height="64px" alt="zig"></a>


Here are the steps to build the project:

* Follow the steps mentioned on the [zig's official site](https://ziglang.org/learn/getting-started/#installing-zig) and setup the language.
* Run the command `zig build-exe src/main.zig` to build the executable
* Run the executable to with `-h/--help` flag to know all the options on how to run the executable.

---

The following project was done as part of **Codecrafters** challenge. You can read more about the codecrafters from below.


This is a starting point for Zig solutions to the
["Build Your Own HTTP server" Challenge](https://app.codecrafters.io/courses/http-server/overview).

[HTTP](https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol) is the
protocol that powers the web. In this challenge, you'll build a HTTP/1.1 server
that is capable of serving multiple clients.

Along the way you'll learn about TCP servers,
[HTTP request syntax](https://www.w3.org/Protocols/rfc2616/rfc2616-sec5.html),
and more.

**Note**: If you're viewing this repo on GitHub, head over to
[codecrafters.io](https://codecrafters.io) to try the challenge.
