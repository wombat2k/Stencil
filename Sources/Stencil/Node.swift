import Foundation

/// Represents a parsed node
public protocol NodeType {
  /// Render the node in the given context
  func render(_ context: Context) throws -> String

  /// Reference to this node's token
  var token: Token? { get }
}

/// Render the collection of nodes in the given context
public func renderNodes(_ nodes: [NodeType], _ context: Context) throws -> String {
  try nodes
    .map { node in
      do {
        return try node.render(context)
      } catch {
        throw error.withToken(node.token)
      }
    }
    .joined()
}

/// Simple node, used for triggering a closure during rendering
public class SimpleNode: NodeType {
  public let handler: (Context) throws -> String
  public let token: Token?

  public init(token: Token, handler: @escaping (Context) throws -> String) {
    self.token = token
    self.handler = handler
  }

  public func render(_ context: Context) throws -> String {
    try handler(context)
  }
}

/// Represents a block of text, renders the text
public class TextNode: NodeType {
  public let text: String
  public let token: Token?
  public let trimBehaviour: TrimBehaviour

  public init(text: String, trimBehaviour: TrimBehaviour = .nothing) {
    self.text = text
    self.token = nil
    self.trimBehaviour = trimBehaviour
  }

  public func render(_ context: Context) throws -> String {
    var string = self.text
    if trimBehaviour.leading != .nothing, !string.isEmpty {
      let range = NSRange(..<string.endIndex, in: string)
      string = TrimBehaviour.leadingRegex(trim: trimBehaviour.leading)
        .stringByReplacingMatches(in: string, options: [], range: range, withTemplate: "")
    }
    if trimBehaviour.trailing != .nothing, !string.isEmpty {
      let range = NSRange(..<string.endIndex, in: string)
      string = TrimBehaviour.trailingRegex(trim: trimBehaviour.trailing)
        .stringByReplacingMatches(in: string, options: [], range: range, withTemplate: "")
    }
    return string
  }
}

/// Representing something that can be resolved in a context
public protocol Resolvable {
  /// Try to resolve this with the given context
  func resolve(_ context: Context) throws -> Any?
}

/// Represents a variable, renders the variable, may have conditional expressions.
public class VariableNode: NodeType {
  public let variable: Resolvable
  public var token: Token?
  let condition: Expression?
  let elseExpression: Resolvable?

  class func parse(_ parser: TokenParser, token: Token) throws -> NodeType {
    let components = token.components

    func hasToken(_ token: String, at index: Int) -> Bool {
      components.count > (index + 1) && components[index] == token
    }

    let condition: Expression?
    let elseExpression: Resolvable?

    if hasToken("if", at: 1) {
      let components = components.suffix(from: 2)
      if let elseIndex = components.firstIndex(of: "else") {
        condition = try parser.compileExpression(components: Array(components.prefix(upTo: elseIndex)), token: token)
        let elseToken = components.suffix(from: elseIndex.advanced(by: 1)).joined(separator: " ")
        elseExpression = try parser.compileResolvable(elseToken, containedIn: token)
      } else {
        condition = try parser.compileExpression(components: Array(components), token: token)
        elseExpression = nil
      }
    } else {
      condition = nil
      elseExpression = nil
    }

    guard let resolvable = components.first else {
      throw TemplateSyntaxError(reason: "Missing variable name", token: token)
    }
    let filter = try parser.compileResolvable(resolvable, containedIn: token)
    return VariableNode(variable: filter, token: token, condition: condition, elseExpression: elseExpression)
  }

  public init(variable: Resolvable, token: Token? = nil) {
    self.variable = variable
    self.token = token
    self.condition = nil
    self.elseExpression = nil
  }

  init(variable: Resolvable, token: Token? = nil, condition: Expression?, elseExpression: Resolvable?) {
    self.variable = variable
    self.token = token
    self.condition = condition
    self.elseExpression = elseExpression
  }

  public init(variable: String, token: Token? = nil) {
    self.variable = Variable(variable)
    self.token = token
    self.condition = nil
    self.elseExpression = nil
  }

  public func render(_ context: Context) throws -> String {
    if let condition = self.condition, try condition.evaluate(context: context) == false {
      return try elseExpression?.resolve(context).map(stringify) ?? ""
    }

    let result = try variable.resolve(context)
    return stringify(result)
  }
}

func stringify(_ result: Any?) -> String {
  if let result = result as? String {
    return result
  } else if let array = result as? [Any?] {
    return unwrap(array).description
  } else if let result = result as? CustomStringConvertible {
    return result.description
  } else if let result = result as? NSObject {
    return result.description
  }

  return ""
}

func unwrap(_ array: [Any?]) -> [Any] {
  array.map { (item: Any?) -> Any in
    if let item = item {
      if let items = item as? [Any?] {
        return unwrap(items)
      } else {
        return item
      }
    } else { return item as Any }
  }
}