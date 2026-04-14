# frozen_string_literal: true

class ReplyBridge

  HOP_HEADER = "X-Postal-Reply-Bridge-Hop"
  TRACE_HEADER = "X-Postal-Reply-Bridge"
  SOURCE_HEADER = "X-Postal-Reply-Bridge-Source"
  MAX_HOPS = 12

  class Result

    attr_accessor :required
    attr_accessor :raw_message
    attr_accessor :bridge_alias
    attr_accessor :error

    def initialize(required:, raw_message:, alias_record: nil, error: nil)
      @required = required
      @raw_message = raw_message
      @bridge_alias = alias_record
      @error = error
    end

    def required?
      required
    end

    def bridged?
      required? && bridge_alias && error.nil?
    end

  end

  class << self

    def prepare_outgoing(server, raw_message, explicit: false)
      mail = Mail.new(raw_message)
      reply_to = single_reply_to(mail)
      required = bridge_required?(server, reply_to, explicit: explicit)
      return Result.new(required: false, raw_message: raw_message) unless required

      readiness_error = readiness_error(server)
      return Result.new(required: true, raw_message: raw_message, error: readiness_error) if readiness_error
      return Result.new(required: true, raw_message: raw_message, error: "Reply Bridge requires exactly one Reply-To address.") if reply_to.blank?

      alias_record = alias_for(server, reply_to)
      mail.reply_to = alias_record.address
      mail[TRACE_HEADER] = "outgoing; alias=#{alias_record.id}"
      alias_record.touch_used!
      Result.new(required: true, raw_message: mail.to_s, alias_record: alias_record)
    end

    def bridge_required?(server, reply_to, explicit: false)
      case server.reply_bridge_mode
      when "ExplicitOnly"
        explicit
      when "AutoExternal"
        reply_to.present? && server.authenticated_domain_for_address(reply_to).nil?
      else
        false
      end
    end

    def readiness_error(server)
      return "Reply Bridge domain is not configured." if server.reply_bridge_domain.blank?
      return "Reply Bridge sender is not configured." if server.reply_bridge_sender.blank?
      return "Reply Bridge sender must use an exact verified domain." if server.reply_bridge_sender_domain.nil?
      return "Reply Bridge sender DNS is not ready." unless server.reply_bridge_sender_status == "OK"
      return "Reply Bridge MX records are not ready." unless server.reply_bridge_mx_status == "OK"

      nil
    end

    def alias_for(server, email)
      email = Postal::Helpers.strip_name_from_address(email).to_s.downcase

      ReplyBridgeAlias.find_by(server: server, email: email) ||
        ReplyBridgeAlias.create!(server: server, email: email)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      ReplyBridgeAlias.find_by!(server: server, email: email)
    end

    def alias_from_address(address)
      uname, domain = address.to_s.downcase.split("@", 2)
      return nil unless uname && domain
      return nil unless uname.start_with?("reply+")

      token = uname.split("+", 2).last
      server = Server.present.find_by(reply_bridge_domain: domain)
      return nil unless server
      return nil unless server.reply_bridge_enabled?

      server.reply_bridge_aliases.active.find_by(token: token)
    end

    def auto_response?(message)
      headers = message.headers
      auto_submitted = headers["auto-submitted"]&.last.to_s.downcase
      precedence = headers["precedence"]&.last.to_s.downcase
      auto_submitted.present? && auto_submitted != "no" || %w[bulk junk list].include?(precedence)
    end

    def loop_detected?(message)
      hop = message.headers[HOP_HEADER.downcase]&.last.to_i
      hop >= MAX_HOPS
    end

    def reemit_reply(incoming_message, alias_record)
      mail = Mail.new(incoming_message.raw_message)
      from = Postal::Helpers.strip_name_from_address(mail.from&.first || incoming_message.mail_from)
      reply_alias = alias_for(alias_record.server, from)

      mail.to = alias_record.email
      mail.from = alias_record.server.reply_bridge_sender
      mail.reply_to = reply_alias.address
      mail[TRACE_HEADER] = "incoming; alias=#{alias_record.id}"
      mail[SOURCE_HEADER] = incoming_message.id.to_s
      mail[HOP_HEADER] = (incoming_message.headers[HOP_HEADER.downcase]&.last.to_i + 1).to_s

      message = alias_record.server.message_db.new_message
      message.scope = "outgoing"
      message.rcpt_to = alias_record.email
      message.mail_from = Postal::Helpers.strip_name_from_address(alias_record.server.reply_bridge_sender)
      message.domain_id = alias_record.server.reply_bridge_sender_domain&.id
      message.raw_message = mail.to_s
      message.reply_bridge_requested = true
      message.reply_bridge_alias_id = reply_alias.id
      message.reply_bridge_source_message_id = incoming_message.id
      message.save

      alias_record.touch_used!
      reply_alias.touch_used!
      message
    end

    private

    def single_reply_to(mail)
      values = Array(mail.reply_to).compact
      return nil unless values.size == 1

      Postal::Helpers.strip_name_from_address(values.first)
    end

  end

end
