Refactor and improve all code in the unleash-server and ops directories for a development environment.
Context:
unleash-server contains Kubernetes manifests and configuration to deploy Unleash.
ops contains GCP Config Connector (KCC) manifests to provision a Cloud SQL instance used by Unleash.
Tasks:
Audit the entire codebase and ensure consistency between both directories.
Validate and fix connectivity between Unleash and Cloud SQL (host, port, credentials, SSL if needed).
Refactor manifests for clarity, simplicity, and DRY principles.
Adapt all configurations for a DEV environment (reduced resources, no HA, simplified setup).
Add or fix missing components: Secrets, ConfigMaps, environment variables, probes.
Apply Kubernetes best practices (labels, selectors, namespaces, structure).
Remove unnecessary or incorrect code.
Ensure the deployment is functional, reproducible, and easy to maintain.
Expected output:
Clean, corrected, and optimized code ready for DEV.
Missing elements added, useless parts removed.
Clear improvements applied across structure and configuration.
