# Serve Active Storage blobs through Rails (proxy) instead of redirecting
# to the internal MinIO URL, which browsers outside the LAN cannot reach.
# MinIO stays as the backend; Chatwoot streams objects server-side. (AA-336/AA-378)
Rails.application.config.active_storage.resolve_model_to_route = :rails_storage_proxy
