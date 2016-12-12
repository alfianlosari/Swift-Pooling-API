import Kitura
import SwiftyJSON
import LoggerAPI
import HeliumLogger
import CouchDB
import Foundation

HeliumLogger.use()

extension String {
    
    var removingHTMLEncoding: String {
        let results = self.replacingOccurrences(of: "+", with: " ")
        return results.removingPercentEncoding ?? results
    }
    
}

let connectionProperties = ConnectionProperties(host: "localhost", port: 5984, secured: false)
let client = CouchDBClient(connectionProperties: connectionProperties)
let database = client.database("polls")

let router = Router()


router.get("/polls/list") { request, response, next in
    database.retrieveAll(includeDocuments: true, callback: { (docs, error) in
        defer { next() }
        if let error = error {
            let errorMessage = error.localizedDescription
            let status = ["status": "error", "message": errorMessage]
            let result = ["result": status]
            let json = JSON(result)
            response.status(.OK).send(json: json)
        } else if let docs = docs {
            let status = ["status": "ok"]
            var polls = [[String: Any]]()
            
            for document in docs["rows"].arrayValue {
                var poll = [String: Any]()
                poll["id"] = document["id"].stringValue
                poll["title"] = document["doc"]["title"].stringValue
                poll["option1"] = document["doc"]["option1"].stringValue
                poll["option2"] = document["doc"]["option2"].stringValue
                poll["votes1"] = document["doc"]["votes1"].intValue
                poll["votes2"] = document["doc"]["votes2"].intValue
                polls.append(poll)
            }
            
            let result: [String: Any] = ["result": status, "polls": polls]
            let json = JSON(result)
            response.status(.OK).send(json: json)
        }
        
        
    })
}

router.post("/polls/create", middleware: BodyParser())
router.post("/polls/create") { (request, response, next) in
    guard let values = request.body else {
        try response.status(.badRequest).end()
        return
    }
    
    guard case .urlEncoded(let body) = values else {
        try response.status(.badRequest).end()
        return
    }
    
    let fields = ["title", "option1", "option2"]
    var poll = [String: Any]()
    
    
    for field in fields {
        if let value = body[field]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if value.characters.count > 0 {
                poll[field] = value.removingHTMLEncoding
                continue
            }
        }
        try response.status(.badRequest).end()
        return
        
    }
    
    poll["votes1"] = 0
    poll["votes2"] = 0
    let json = JSON(poll)
    
    database.create(json, callback: { (id, revision, doc, error) in
        defer { next() }
        if let id = id {
            let status = ["status": "ok", "id": id]
            let result = ["result": status]
            let json = JSON(result)
            response.status(.OK).send(json: json)
        } else {
            let errorMessage = error?.localizedDescription ?? "Unknown Error"
            let status = ["status": "error", "message": errorMessage]
            let result = ["result": status]
            let json = JSON(result)
            response.status(.internalServerError).send(json: json)
        }
    })
}

router.post("/polls/vote/:pollid/:option") { (request, response, next) in
    guard let poll = request.parameters["pollid"],
        let option = request.parameters["option"]
        else {
            try response.status(.badRequest).end()
            return
    }
    
    database.retrieve(poll, callback: { (doc, error) in
        if let error = error {
            let errorMessage = error.localizedDescription
            let status = ["status": "error", "message": errorMessage]
            let result = ["result": status]
            let json = JSON(result)
            response.status(.notFound).send(json: json)
            next()
        } else if let doc = doc {
            var newDocument = doc
            let id = doc["_id"].stringValue
            let rev = doc["_rev"].stringValue
            
            
            if option == "1" {
                newDocument["votes1"].intValue += 1
            } else if option == "2" {
                newDocument["votes2"].intValue += 1
            }
            
            database.update(id, rev: rev, document: newDocument, callback: { (rev, doc, error) in
                defer { next() }
                if let error = error {
                    let status = ["status": "error"]
                    let result = ["result": status]
                    let json = JSON(result)
                    response.status(.conflict).send(json: json)
                } else {
                    let status = ["status": "ok"]
                    let result = ["result": status]
                    let json = JSON(result)
                    response.status(.OK).send(json: json)
                }
            })
        }
    })

}


router.delete("/polls/vote/:pollid") { (request, response, next) in
    guard let poll = request.parameters["pollid"] else {
        try response.status(.badRequest).end()
        return
    }
    
    database.retrieve(poll, callback: { (doc, error) in
        if let error = error {
            let errorMessge = error.localizedDescription
            let status = ["status": "error", "message": error.localizedDescription]
            let result = ["result": status]
            let json = JSON(result)
            response.status(.notFound).send(json: json)
            next()
        } else if let doc = doc {
            let id = doc["_id"].stringValue
            let rev = doc["_rev"].stringValue
            database.delete(id, rev: rev, callback: { (error) in
                defer { next() }
                if let error = error {
                    let errorMessage = error.localizedDescription
                    let status = ["status": "error", "messsage": errorMessage]
                    let result = ["result": status]
                    let json = JSON(result)
                    response.status(.badRequest).send(json: json)
                } else {
                    let status = ["status": "ok"]
                    let result = ["result": status]
                    let json = JSON(result)
                    response.status(.OK).send(json: json)
                }
                
            })
        }

    })
    
    
}

Kitura.addHTTPServer(onPort: 8090, with: router)
Kitura.run()
