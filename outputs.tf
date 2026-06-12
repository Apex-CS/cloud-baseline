output "name_prefix" {
  description = "Standard prefix for naming resources."
  value       = local.name_prefix
}

output "tags" {
  description = "Normalized and ready-to-use tags/labels map."
  value       = local.tags
}