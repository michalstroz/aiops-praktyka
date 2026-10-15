variable "kubeconfig_path" {
  description = "Ścieżka do kubeconfigu (ten sam, którego używa kubectl)."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kontekst z kubeconfigu wskazujący klaster aiops."
  type        = string
  default     = "aiops"
}

variable "namespace" {
  description = "Namespace uczestnika, w którym działa Kantyna."
  type        = string
  default     = "michal"
}
