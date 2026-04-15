# frozen_string_literal: true

class ReplyBridgeAlias < ApplicationRecord

  belongs_to :server

  validates :email, presence: true, format: { with: /@/ }, uniqueness: { scope: :server_id, case_sensitive: false }
  validates :token, presence: true, uniqueness: true

  before_validation :normalize_email
  before_validation :ensure_token
  before_validation :ensure_expiry

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :matching, lambda { |query|
    query = query.to_s.strip.downcase
    next all if query.blank?

    token = token_from_alias_address(query) || query
    pattern = "%#{sanitize_sql_like(query)}%"
    token_pattern = "%#{sanitize_sql_like(token)}%"
    where("LOWER(email) LIKE :pattern OR token LIKE :token_pattern", pattern: pattern, token_pattern: token_pattern)
  }

  def address
    "reply+#{token}@#{server.reply_bridge_domain}"
  end

  def touch_used!
    update_columns(last_used_at: Time.current, expires_at: default_expiry)
  end

  private

  def normalize_email
    self.email = Postal::Helpers.strip_name_from_address(email).to_s.downcase.presence
  end

  def ensure_token
    self.token ||= SecureRandom.alphanumeric(16).downcase
  end

  def ensure_expiry
    self.expires_at ||= default_expiry
  end

  def default_expiry
    server.reply_bridge_alias_ttl_days.to_i.days.from_now
  end

  class << self

    def token_from_alias_address(address)
      uname, _domain = address.to_s.downcase.split("@", 2)
      return nil unless uname&.start_with?("reply+")

      uname.split("+", 2).last.presence
    end

  end

end
