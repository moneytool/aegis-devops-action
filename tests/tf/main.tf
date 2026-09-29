# A provider-free configuration for the action's own tests: terraform_data is built in,
# so `terraform init` downloads nothing and `plan` needs no credentials.
resource "terraform_data" "example" {
  input = "aegis-devops-action self-test"
}
