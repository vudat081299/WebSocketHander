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

import Fluent
import Vapor
import Leaf

struct QuestionsController: RouteCollection {
  let wsController: WebSocketController
  
  func boot(routes: RoutesBuilder) throws {
    routes.webSocket("socket", onUpgrade: self.webSocket)
    routes.get(use: index)
    routes.post(":questionId", "answer", use: answer)
  }
  
  func webSocket(req: Request, socket: WebSocket) {
    self.wsController.connect(socket)
  }
  
  struct QuestionsContext: Encodable {
    let questions: [Question]
  }

  func index(req: Request) throws -> EventLoopFuture<View> {
    // 1
    Question.query(on: req.db).all().flatMap {
      // 2
      return req.view.render("questions", QuestionsContext(questions: $0))
    }
  }
  
  func answer(req: Request) throws -> EventLoopFuture<Response> {
    // 1
    guard let questionId = req.parameters.get("questionId"), let questionUid = UUID(questionId) else {
      throw Abort(.badRequest)
    }
    // 2
    return Question.find(questionUid, on: req.db).unwrap(or: Abort(.notFound)).flatMap { question in
      question.answered = true
      // 3
      return question.save(on: req.db).flatMapThrowing {
        // 4
        try self.wsController.send(message: QuestionAnsweredMessage(questionId: question.requireID()), to: .id(question.askedFrom))
        // 5
        return req.redirect(to: "/")
      }
    }
  }
}
