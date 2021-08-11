/// Copyright (c) 2020 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// This project and source code may use libraries or frameworks that are
/// released under various Open-Source licenses. Use of those libraries and
/// frameworks are governed by their own individual licenses.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import Vapor
import Fluent

enum WebSocketSendOption {
  case id(UUID), socket(WebSocket)
}

class WebSocketController {
  let lock: Lock
  var sockets: [UUID: WebSocket]
  let db: Database
  let logger: Logger
  
  init(db: Database) {
    self.lock = Lock()
    self.sockets = [:]
    self.db = db
    self.logger = Logger(label: "WebSocketController")
  }
  
  func connect(_ ws: WebSocket) {
    // 1
    let uuid = UUID()
    self.lock.withLockVoid {
      self.sockets[uuid] = ws
    }
    // 2
    ws.onBinary { [weak self] ws, buffer in
      guard let self = self, let data = buffer.getData(at: buffer.readerIndex, length: buffer.readableBytes) else { return }
      self.onData(ws, data)
    }
    // 3
    ws.onText { [weak self] ws, text in
      guard let self = self, let data = text.data(using: .utf8) else { return }
      self.onData(ws, data)
    }
    // 4
    self.send(message: QnAHandshake(id: uuid), to: .socket(ws))
  }
  
  func send<T: Codable>(message: T, to sendOption: WebSocketSendOption) {
    logger.info("Sending \(T.self) to \(sendOption)")
    do {
      // 1
      let sockets: [WebSocket] = self.lock.withLock {
        switch sendOption {
        case .id(let id):
          return [self.sockets[id]].compactMap { $0 }
        case .socket(let socket):
          return [socket]
        }
      }
      
      // 2
      let encoder = JSONEncoder()
      let data = try encoder.encode(message)
      
      // 3
      sockets.forEach {
        $0.send(raw: data, opcode: .binary)
      }
    } catch {
      logger.report(error: error)
    }
  }
  
  func onNewQuestion(_ ws: WebSocket, _ id: UUID, _ message: NewQuestionMessage) {
    let q = Question(content: message.content, askedFrom: id)
    self.db.withConnection {
      // 1
      q.save(on: $0)
    }.whenComplete { res in
      let success: Bool
      let message: String
      switch res {
      case .failure(let err):
        // 2
        self.logger.report(error: err)
        success = false
        message = "Something went wrong creating the question."
      case .success:
        // 3
        self.logger.info("Got a new question!")
        success = true
        message = "Question created. We will answer it as soon as possible :]"
      }
      // 4
      try? self.send(message: NewQuestionResponse(
        success: success,
        message: message,
        id: q.requireID(),
        answered: q.answered,
        content: q.content,
        createdAt: q.createdAt
      ), to: .socket(ws))
    }
  }
  
  func onData(_ ws: WebSocket, _ data: Data) {
    let decoder = JSONDecoder()
    do {
      // 1
      let sinData = try decoder.decode(QnAMessageSinData.self, from: data)
      // 2
      switch sinData.type {
      case .newQuestion:
        // 3
        let newQuestionData = try decoder.decode(NewQuestionMessage.self, from: data)
        self.onNewQuestion(ws, sinData.id, newQuestionData)
      default:
        break
      }
    } catch {
      logger.report(error: error)
    }
  }
}
