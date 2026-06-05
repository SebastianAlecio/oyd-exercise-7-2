resource "aws_sqs_queue" "main" {
  name                       = var.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
}

# Pipeline evidence: ejercicio 7.2 — corrida con branch protection activa
