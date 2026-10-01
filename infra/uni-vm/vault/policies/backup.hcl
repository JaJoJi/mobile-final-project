# Daily backup job: take Raft snapshots, nothing else.
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
