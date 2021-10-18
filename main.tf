provider "aws" {
}

resource "random_id" "id" {
  byte_length = 8
}

resource "aws_iam_role" "appsync" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "appsync.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "appsync" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
			"dynamodb:Query",
			"dynamodb:Scan",
    ]
    resources = [
			module.database.users_table_arn,
			module.database.todos_table_arn,
    ]
  }
}

resource "aws_iam_role_policy" "appsync" {
  role   = aws_iam_role.appsync.id
  policy = data.aws_iam_policy_document.appsync.json
}

resource "aws_appsync_graphql_api" "appsync" {
  name                = "appsync_test"
  schema              = file("schema.graphql")
  authentication_type = "AWS_IAM"
}

module "database" {
	source = "./modules/database"
}

resource "aws_appsync_datasource" "users" {
  api_id           = aws_appsync_graphql_api.appsync.id
  name             = "users"
  service_role_arn = aws_iam_role.appsync.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = module.database.users_table_name
  }
}

resource "aws_appsync_datasource" "todos" {
  api_id           = aws_appsync_graphql_api.appsync.id
  name             = "todos"
  service_role_arn = aws_iam_role.appsync.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = module.database.todos_table_name
  }
}

# resolvers

resource "aws_appsync_resolver" "Query_user" {
  api_id      = aws_appsync_graphql_api.appsync.id
  type        = "Query"
  field       = "user"
  data_source = aws_appsync_datasource.users.name

  request_template = <<EOF
{
	"version" : "2018-05-29",
	"operation" : "GetItem",
	"key" : {
		"id": {"S": $util.toJson($ctx.args.id)}
	},
	"consistentRead" : true
}
EOF

  response_template = <<EOF
#if ($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOF
}

resource "aws_appsync_resolver" "Query_allUsers" {
  api_id      = aws_appsync_graphql_api.appsync.id
  type        = "Query"
  field       = "allUsers"
  data_source = aws_appsync_datasource.users.name

  request_template = <<EOF
{
	"version" : "2018-05-29",
	"operation" : "Scan"
}
EOF

  response_template = <<EOF
#if ($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
$utils.toJson($ctx.result.items)
EOF
}

resource "aws_appsync_resolver" "Mutation_addTodo" {
  api_id      = aws_appsync_graphql_api.appsync.id
  type        = "Mutation"
  field       = "addTodo"

  data_source = aws_appsync_datasource.todos.name
  request_template = <<EOF
{
	"version" : "2018-05-29",
	"operation" : "PutItem",
	"key" : {
		"userid": {"S": $util.toJson($ctx.arguments.userId)},
		"id": {"S": $util.toJson($util.autoId())}
	},
	"attributeValues": {
		"checked": {"BOOL": false},
		"name": {"S": $util.toJson($ctx.arguments.name)}
	}
}
EOF

  response_template = <<EOF
#if ($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOF
}

resource "aws_appsync_resolver" "User_todos_1" {
  api_id      = aws_appsync_graphql_api.appsync.id
  type        = "User"
  field       = "todos"

  data_source = aws_appsync_datasource.todos.name
  request_template = <<EOF
{
	"version" : "2018-05-29",
	"operation" : "Query",
	"query" : {
		"expression": "userid = :userid",
			"expressionValues" : {
				":userid" : $util.dynamodb.toDynamoDBJson($ctx.source.id)
			}
	}
}
EOF

  response_template = <<EOF
#if ($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
$utils.toJson($ctx.result.items)
EOF
}

resource "aws_appsync_resolver" "Todo_user" {
  api_id      = aws_appsync_graphql_api.appsync.id
  type        = "Todo"
  field       = "user"
  data_source = aws_appsync_datasource.users.name

  request_template = <<EOF
{
	"version" : "2018-05-29",
	"operation" : "GetItem",
	"key" : {
		"id": {"S": $util.toJson($ctx.source.userid)}
	},
	"consistentRead" : true
}
EOF

  response_template = <<EOF
#if ($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOF
}

