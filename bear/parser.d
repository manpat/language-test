module bear.parser;

import std.stdio;
import std.conv;
import bear.tokeniser : Token;
import bear.ast;
import bear.parserdebug;

class Parser {
	private alias TT = Token.Type;
	private alias AT = ASTNode.NodeType;
	private Token[] tokens;
	private Token* next;

	ASTNode* Parse(Token[] _tokens){
		tokens = _tokens;

		return ParseProgram();
	}

private:
	void Error(ST)(ST e){
		throw new Exception("parser: " ~ to!string(e));
	}

	void InternalError(ST)(ST e){
		throw new Exception("parser internal: " ~ to!string(e));
	}

	void ReadNext(){
		static ulong pos = 0;

		if(pos >= tokens.length) {
			next = null;
		}else{
			next = &tokens[pos++];
		}
	}

	Token* Match(TT type){
		if(!next){
			if(type != TT.EOF){
				throw new Exception("Unexpected EOF");
			}
		}else{
			if(next.type != type){
				throw new Exception("Expected " ~ to!string(type) ~ ", got " ~ to!string(next.type));
			}else{
				auto c = next;
				ReadNext();
				ScopeDebug.Write("matched " ~ to!string(c.type));

				return c;
			}
		}

		return null;
	}

	bool Check(TT type){
		if(!next){
			return type == TT.EOF; 
		}

		return next.type == type;
	}

	//////////////////////////////////////////////////////

	// Start /////////////////////////////////////////////

	ASTNode* ParseProgram(){
		auto __sd = ScopeDebug("ParseProgram");
		ASTNode* node = null;
		ReadNext();

		if(!Check(TT.EOF)){
			node = ParseStatementList();
		}

		Match(TT.EOF);

		return node;
	}

	// Statements ////////////////////////////////////////

	ASTNode* ParseStatementList(){
		auto __sd = ScopeDebug("ParseStatementList");
		ASTNode* node = null;

		if(Check(TT.EOF)) return null;

		auto first = ParseStatement();
		if(first){
			if(!Check(TT.EOF) && !Check(TT.RightBrace)){
				node = new ASTNode(AT.StatementList);
				node.list ~= first;

				do{
					node.list ~= ParseStatement();
				
				}while(!Check(TT.EOF) && !Check(TT.RightBrace));

			}else{
				node = first;
			}
		}

		return node;
	}

	ASTNode* ParseStatement(){
		auto __sd = ScopeDebug("ParseStatement");
		ASTNode* node = null;

		if(Check(TT.Identifier)){
			node = ParseDeclAssignOrFuncCall();

		}else if(Check(TT.Function)){
			node = ParseFuncDeclOrDef();

		}else if(Check(TT.Return)){
			node = ParseReturn();

		}else if(Check(TT.LeftBrace)){
			node = ParseBlock();

		}else if(Check(TT.If)){
			node = ParseConditionalStatement();

		}else if(Check(TT.For) || Check(TT.While)
			|| Check(TT.Do) || Check(TT.Foreach)){ // foreach is v2
			node = ParseLoop();

		}else{
			if(!Check(TT.RightBrace))
				Error("Statements cannot begin with " ~ to!string(next.type));
		}

		return node;
	}

	// Declarations and Assignments //////////////////////

	ASTNode* ParseDeclAssignOrFuncCall(){
		auto __sd = ScopeDebug("ParseDeclAssignOrFuncCall");
		auto id = ParseIdentifier();
		ASTNode* node = null;

		if(Check(TT.LeftParen)){
			node = ParseFuncCall(id);

		}else if(Check(TT.LeftSquare)){
			node = new ASTNode(AT.Assignment);
			node.left = ParseArraySubscript(id);
			node.right = ParseAssignmentStub();

		}else{
			auto type = ParseOptionalType();
			if(type) {
				node = new ASTNode(AT.Declaration);
				node.typeinfo = type.typeinfo;

				destroy(type);
				type = null;
			}

			auto assign = ParseOptionalAssign();
			if(assign){
				if(!node) node = new ASTNode(AT.Assignment);
				node.right = assign;

			}

			if(!node){
				Error("An identifier at the beginning of a statement must form either a type or an assignment");
			}

			node.left = id;
		}

		Match(TT.SemiColon);
		return node;
	}

	ASTNode* ParseOptionalType(){
		auto __sd = ScopeDebug("ParseOptionalType");

		if(Check(TT.Type)){
			return ParseType();
		}

		return null;
	}

	ASTNode* ParseOptionalAssign(){
		auto __sd = ScopeDebug("ParseOptionalAssign");
		
		if(Check(TT.Assign)){
			return ParseAssignmentStub();
		}

		return null;
	}

	ASTNode* ParseAssignmentStub(){
		auto __sd = ScopeDebug("ParseAssignmentStub");

		Match(TT.Assign);
		return ParseExpression();
	}

	ASTNode* ParseBlock(){
		auto __sd = ScopeDebug("ParseBlock");
		ASTNode* node;

		Match(TT.LeftBrace);
		node = ParseStatementList();
		Match(TT.RightBrace);

		return node;
	}

	// Function calls ////////////////////////////////////

	ASTNode* ParseFuncCall(ASTNode* id){
		auto __sd = ScopeDebug("ParseFuncCall");
		auto node = new ASTNode(AT.FunctionCall);
		node.left = id;

		Match(TT.LeftParen);
		node.right = ParseArgumentList();
		Match(TT.RightParen);

		return node;
	}

	ASTNode* ParseArgumentList(){
		auto __sd = ScopeDebug("ParseArgumentList");

		if(!Check(TT.RightParen)){
			auto node = new ASTNode(AT.FunctionArgumentList);
			node.list ~= ParseNonTupleExpression();

			while(Check(TT.Comma)){
				Match(TT.Comma);
				node.list ~= ParseNonTupleExpression();
			}

			return node;
		}

		return null;
	}

	// Function Declarations and Definitions /////////////

	ASTNode* ParseFuncDeclOrDef(){
		auto __sd = ScopeDebug("ParseFuncDeclOrDef");
		Match(TT.Function);

		auto node = new ASTNode(AT.FunctionDeclaration);
		node.functioninfo = new ASTFunctionInfo;

		node.left = ParseIdentifier(); // Remove for lambdas?

		node.functioninfo.parameterList = ParseFuncDeclParam();
		node.functioninfo.returnType = ParseFuncDeclType();

		if(Check(TT.LeftBrace)){
			node.type = AT.FunctionDefinition;
			node.right = ParseBlock();
		}else{
			Match(TT.SemiColon);
		}

		return node;
	}

	ASTNode* ParseFuncDeclParam(){
		auto __sd = ScopeDebug("ParseFuncDeclParam");
		ASTNode* node = null;

		if(Check(TT.LeftParen)){
			Match(TT.LeftParen);
			node = ParseParameterList();
			Match(TT.RightParen);
		}

		return node;
	}

	ASTNode* ParseFuncDeclType(){
		auto __sd = ScopeDebug("ParseFuncDeclType");

		if(Check(TT.Returns)){
			Match(TT.Returns);
			return ParseType();
		}

		return null;
	}

	ASTNode* ParseParameterList(){
		auto __sd = ScopeDebug("ParseParameterList");

		if(Check(TT.Identifier)){
			auto first = ParseParameter();

			if(Check(TT.Comma) && first){
				auto plist = new ASTNode(AT.FunctionParameterList);
				plist.list ~= first;

				do{
					Match(TT.Comma);
					plist.list ~= ParseParameter();

				} while(Check(TT.Comma));

				return plist;
			}

			return first;
		}

		return null;
	}

	ASTNode* ParseParameter(){
		auto __sd = ScopeDebug("ParseParameter");
		auto param = new ASTNode(AT.FunctionParameter);

		if(Check(TT.Identifier)){
			param.left = ParseIdentifier();
		}

		param.right = ParseType();

		return param;
	}

	ASTNode* ParseReturn(){
		auto __sd = ScopeDebug("ParseReturn");

		Match(TT.Return);
		auto node = new ASTNode(AT.ReturnStatement);
		node.left = ParseExpression();
		Match(TT.SemiColon);

		return node;
	}

	// Expressions ///////////////////////////////////////

	ASTNode* ParseExpression(){
		auto __sd = ScopeDebug("ParseExpression");
		auto node = ParseNonTupleExpression();

		node = ParseTuple(node);

		return node;
	}

	ASTNode* ParseTuple(ASTNode* node){
		auto __sd = ScopeDebug("ParseExpressionR");

		if(Check(TT.Comma)){
			auto first = node;
			node = new ASTNode(AT.Tuple);
			node.list ~= first;

			do{
				Match(TT.Comma);
				node.list ~= ParseNonTupleExpression();
				
			}while(Check(TT.Comma));
		}

		return node;
	}

	// Just for convenience
	alias ParseNonTupleExpression = ParseComparisonOpPrecedence;

	ASTNode* ParseComparisonOpPrecedence(){
		auto __sd = ScopeDebug("ParseComparisonOpPrecedence");
		auto node = ParseBinOpAddPrecedence();

		node = ParseComparisonOpPrecedenceR(node);

		return node;
	}

	ASTNode* ParseComparisonOpPrecedenceR(ASTNode* node){
		auto __sd = ScopeDebug("ParseComparisonOpPrecedenceR");
		ASTNode* op = null;

		if(Check(TT.Equals)){
			Match(TT.Equals);
			op = new ASTNode(AT.Equals);

		}else if(Check(TT.NEquals)){
			Match(TT.NEquals);
			op = new ASTNode(AT.NEquals);

		}else if(Check(TT.LEquals)){
			Match(TT.LEquals);
			op = new ASTNode(AT.LEquals);

		}else if(Check(TT.GEquals)){
			Match(TT.GEquals);
			op = new ASTNode(AT.GEquals);

		}else if(Check(TT.LessThan)){
			Match(TT.LessThan);
			op = new ASTNode(AT.LessThan);

		}else if(Check(TT.GreaterThan)){
			Match(TT.GreaterThan);
			op = new ASTNode(AT.GreaterThan);
		}

		if(op){
			op.left = node;
			op.right = ParseBinOpAddPrecedence();
			node = op;

			// Non associative so no recurse
		}

		return node;
	}

	ASTNode* ParseBinOpAddPrecedence(){
		auto __sd = ScopeDebug("ParseBinOpAddPrecedence");
		auto node = ParseBinOpMulPrecedence();

		node = ParseBinOpAddPrecedenceR(node);

		return node;
	}

	ASTNode* ParseBinOpAddPrecedenceR(ASTNode* node){
		auto __sd = ScopeDebug("ParseBinOpAddPrecedenceR");
		ASTNode* op = null;

		if(Check(TT.Plus)){
			Match(TT.Plus);
			op = new ASTNode(AT.Plus);

		}else if(Check(TT.Minus)){
			Match(TT.Minus);
			op = new ASTNode(AT.Minus);
		}

		if(op){
			op.left = node;
			op.right = ParseBinOpMulPrecedence();
			node = op;

			// Left associative so recurse
			node = ParseBinOpAddPrecedenceR(node);
		}

		return node;
	}

	ASTNode* ParseBinOpMulPrecedence(){
		auto __sd = ScopeDebug("ParseBinOpMulPrecedence");
		auto node = ParseUnaryOp();

		node = ParseBinOpMulPrecedenceR(node);

		return node;
	}

	ASTNode* ParseBinOpMulPrecedenceR(ASTNode* node){
		auto __sd = ScopeDebug("ParseBinOpMulPrecedenceR");
		ASTNode* op = null;

		if(Check(TT.Star)){
			Match(TT.Star);
			op = new ASTNode(AT.Times);

		}else if(Check(TT.Divide)){
			Match(TT.Divide);
			op = new ASTNode(AT.Divide);
		}

		if(op){
			op.left = node;
			node = op;
			node.right = ParseUnaryOp();

			// Left associative so recurse
			node = ParseBinOpMulPrecedenceR(node);
		}

		return node;
	}

	ASTNode* ParseUnaryOp(){
		auto __sd = ScopeDebug("ParseUnaryOp");
		ASTNode* op = null;

		if(Check(TT.Minus)){
			Match(TT.Minus);
			op = new ASTNode(AT.Negate);

		}else if(Check(TT.At)){
			Match(TT.At);
			op = new ASTNode(AT.AddressOf);
			
		}else if(Check(TT.Pointer)){
			Match(TT.Pointer);
			op = new ASTNode(AT.Deref);
			
		}else if(Check(TT.Not)){
			Match(TT.Not);
			op = new ASTNode(AT.Not);
		}

		if(op){
			op.left = ParseUnaryOp();
			return op;
		}

		return ParseExpressionTerm();
	}

	ASTNode* ParseExpressionTerm(){
		auto __sd = ScopeDebug("ParseExpressionTerm");
		ASTNode* node = null;

		if(Check(TT.LeftParen)){
			Match(TT.LeftParen);
			node = ParseExpression();
			Match(TT.RightParen);

		}else if(Check(TT.Number)){
			node = ParseNumber();

		}else if(Check(TT.Identifier)){
			node = ParseIdentifier();

			if(Check(TT.Assign)){
				auto left = node;
				node = new ASTNode(AT.Assignment);
				node.left = left;
				node.right = ParseAssignmentStub();
			}else if(Check(TT.LeftSquare)){
				node = ParseArraySubscript(node);
			}

		}else if(Check(TT.String)){
			node = ParseString();

		}else if(Check(TT.LanguageConstant)){
			node = ParseLanguageConstant();
		}

		return node;
	}

	ASTNode* ParseArraySubscript(ASTNode* id){
		Match(TT.LeftSquare);
		auto node = new ASTNode(AT.ArraySubscript);
		node.left = id;
		node.right = ParseExpression();
		Match(TT.RightSquare);

		return node;
	}

	// Types /////////////////////////////////////////////

	ASTNode* ParseType(){
		auto __sd = ScopeDebug("ParseType");
		auto base = ParseBaseType();

		base = ParseTypeModifiers(base);

		return base;
	}

	ASTNode* ParseTypeModifiers(ASTNode* base){
		auto __sd = ScopeDebug("ParseTypeModifiers");

		if(Check(TT.Pointer)){
			Match(TT.Pointer);
			base.typeinfo.pointerLevel++;

			base = ParseTypeModifiers(base);
		}else if(Check(TT.LeftSquare)){
			Match(TT.LeftSquare);

			if(!Check(TT.RightSquare)){
				auto subscript = ParseExpression();
				destroy(subscript);
				// TODO: something here /////////////////////////
			}

			Match(TT.RightSquare);
		}

		return base;
	}
	
	ASTNode* ParseBaseType(){
		auto __sd = ScopeDebug("ParseBaseType");
		auto tok = Match(TT.Type);
		auto node = new ASTNode(AT.Type);
		node.typeinfo = new ASTTypeInfo;

		// TODO: actually do type stuff /////////////////////////

		return node;
	}

	// Conditional Statements ////////////////////////////

	ASTNode* ParseConditionalStatement(){
		auto __sd = ScopeDebug("ParseConditionalStatement");
		Match(TT.If);
		auto node = new ASTNode(AT.ConditionalStatement);
		node.left = ParseCondition();
		node.right = ParseStatement();

		if(Check(TT.Else)){
			Match(TT.Else);
			node.third = ParseStatement();
		}

		return node;
	}

	ASTNode* ParseCondition(){
		auto __sd = ScopeDebug("ParseCondition");
		Match(TT.LeftParen);
		auto cond = ParseExpression();
		Match(TT.RightParen);

		return cond;
	}

	// Loops /////////////////////////////////////////////

	ASTNode* ParseLoop(){
		auto __sd = ScopeDebug("ParseLoop");
		ASTNode* node = null;
		
		if(Check(TT.For)){
			node = ParseForLoop();

		}else if(Check(TT.While)){
			node = ParseWhileLoop();

		}else if(Check(TT.Do)){
			node = ParseDoLoop();

		}else if(Check(TT.Foreach)){
			node = ParseForeachLoop();

		}else{
			Error("Tried to parse a loop that wasn't a loop " ~ next.text);
		}

		return node;
	}

	ASTNode* ParseForLoop(){
		auto __sd = ScopeDebug("ParseForLoop");
		auto node = new ASTNode(AT.Loop);
		Match(TT.For);

		if(Check(TT.LeftParen)){
			Match(TT.LeftParen);
			//node.left = ParseExpression();
			InternalError("I don't know how to parse for loops");
			Match(TT.RightParen);
		}

		node.right = ParseStatement();

		return node;
	}

	ASTNode* ParseWhileLoop(){
		auto __sd = ScopeDebug("ParseWhileLoop");
		auto node = new ASTNode(AT.Loop);
		Match(TT.While);
		Match(TT.LeftParen);
		node.left = ParseExpression();
		Match(TT.RightParen);

		node.right = ParseStatement();

		return node;
	}

	ASTNode* ParseDoLoop(){
		auto __sd = ScopeDebug("ParseDoLoop");
		auto node = new ASTNode(AT.Loop);
		Match(TT.Do);
		node.right = ParseStatement();
		Match(TT.While);
		Match(TT.LeftParen);
		node.left = ParseExpression();
		Match(TT.RightParen);
		Match(TT.SemiColon);

		return node;
	}

	ASTNode* ParseForeachLoop(){
		auto __sd = ScopeDebug("ParseForeachLoop");
		auto node = new ASTNode(AT.Loop);
		Match(TT.Foreach);

		Error("foreach is v2 feature");
		return null;
	}

	// Terminals /////////////////////////////////////////

	ASTNode* ParseIdentifier(){
		auto __sd = ScopeDebug("ParseIdentifier");
		auto tok = Match(TT.Identifier);
		auto node = new ASTNode(AT.Identifier);
		node.name = tok.text;

		return node;
	}
	
	ASTNode* ParseNumber(){
		auto __sd = ScopeDebug("ParseNumber");
		auto tok = Match(TT.Number);
		auto node = new ASTNode(AT.Number);
		node.literalinfo = new ASTLiteralInfo;
		node.literalinfo.text = tok.text;

		return node;
	}
	
	ASTNode* ParseString(){
		auto __sd = ScopeDebug("ParseString");
		auto tok = Match(TT.String);
		auto node = new ASTNode(AT.String);
		node.literalinfo = new ASTLiteralInfo;
		node.literalinfo.text = tok.text[1..$-1]; // strip quotation marks

		return node;
	}
	
	ASTNode* ParseLanguageConstant(){
		auto __sd = ScopeDebug("ParseLanguageConstant");
		auto tok = Match(TT.LanguageConstant);
		ASTNode* node = null;

		switch(tok.text){
			case "true":
				node = new ASTNode(AT.TrueConstant);
				break;
			case "false":
				node = new ASTNode(AT.FalseConstant);
				break;
			case "null":
				node = new ASTNode(AT.NullConstant);
				break;

			default:
				Error("Unknown language constant " ~ tok.text);
		}

		// Language constants are literals too
		node.literalinfo = new ASTLiteralInfo;
		node.literalinfo.text = tok.text;

		return node;
	}
}