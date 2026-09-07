variable "name_prefix" {
  description = "Prefix applied to every IAM role name this module creates (e.g. \"taskflow-dev\")."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
