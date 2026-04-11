class WorkspaceProviderCredential < ApplicationRecord
  PROVIDERS = %w[slack transactional_email].freeze
  CREDENTIAL_TYPES = %w[api_credential delegated_oauth browser_session].freeze

  belongs_to :workspace

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :credential_type, presence: true, inclusion: { in: CREDENTIAL_TYPES }
  validates :workspace_id, uniqueness: { scope: :provider }
end
