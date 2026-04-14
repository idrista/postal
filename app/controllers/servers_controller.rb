# frozen_string_literal: true

class ServersController < ApplicationController

  include WithinOrganization

  before_action :admin_required, only: [:advanced, :suspend, :unsuspend]
  before_action { params[:id] && @server = organization.servers.present.find_by_permalink!(params[:id]) }

  def index
    @servers = organization.servers.present.order(:name).to_a
  end

  def show
    if @server.created_at < 48.hours.ago
      @graph_type = :daily
      graph_data = @server.message_db.statistics.get(:daily, [:incoming, :outgoing, :bounces], Time.now, 30)
    elsif @server.created_at < 24.hours.ago
      @graph_type = :hourly
      graph_data = @server.message_db.statistics.get(:hourly, [:incoming, :outgoing, :bounces], Time.now, 48)
    else
      @graph_type = :hourly
      graph_data = @server.message_db.statistics.get(:hourly, [:incoming, :outgoing, :bounces], Time.now, 24)
    end
    @first_date = graph_data.first.first
    @last_date = graph_data.last.first
    @graph_data = graph_data.map(&:last)
    @messages = @server.message_db.messages(order: "id", direction: "desc", limit: 6)
  end

  def new
    @server = organization.servers.build
  end

  def create
    @server = organization.servers.build(safe_params(:permalink))
    if @server.save
      redirect_to_with_json organization_server_path(organization, @server)
    else
      render_form_errors "new", @server
    end
  end

  def update
    extra_params = [:spam_threshold, :spam_failure_threshold, :postmaster_address]

    if current_user.admin?
      extra_params += [
        :send_limit,
        :allow_sender,
        :privacy_mode,
        :log_smtp_data,
        :outbound_spam_threshold,
        :message_retention_days,
        :raw_message_retention_days,
        :raw_message_retention_size,
      ]
    end

    if @server.update(safe_params(*extra_params))
      redirect_to_with_json organization_server_path(organization, @server), notice: "Server settings have been updated"
    else
      render_form_errors "edit", @server
    end
  end

  def destroy
    if params[:confirm_text].blank? || params[:confirm_text].downcase.strip != @server.name.downcase.strip
      respond_to do |wants|
        alert_text = "The text you entered does not match the server name. Please check and try again."
        wants.html { redirect_to organization_delete_path(@organization), alert: alert_text }
        wants.json { render json: { alert: alert_text } }
      end
      return
    end

    @server.soft_destroy
    redirect_to_with_json organization_root_path(organization), notice: "#{@server.name} has been deleted successfully"
  end

  def queue
    @messages = @server.queued_messages.order(id: :desc).page(params[:page]).includes(:ip_address)
    @messages_with_message = @messages.include_message
  end

  def suspend
    @server.suspend(params[:reason])
    redirect_to_with_json [organization, @server], notice: "Server has been suspended"
  end

  def unsuspend
    @server.unsuspend
    redirect_to_with_json [organization, @server], notice: "Server has been unsuspended"
  end

  def reply_bridge
  end

  def check_reply_bridge
    if @server.check_reply_bridge
      redirect_to_with_json [:reply_bridge, organization, @server], notice: "Reply Bridge is ready."
    else
      redirect_to_with_json [:reply_bridge, organization, @server], alert: "Reply Bridge is not ready yet. Check the details below."
    end
  end

  def test_reply_bridge
    unless @server.reply_bridge_ready?
      redirect_to_with_json [:reply_bridge, organization, @server], alert: "Reply Bridge must be ready before sending a test."
      return
    end

    alias_record = ReplyBridge.alias_for(@server, current_user.email_address)
    mail = Mail.new
    mail.from = "reply-bridge-test@example.net"
    mail.to = alias_record.address
    mail.subject = "Reply Bridge test"
    mail.body = "This is an automated Reply Bridge test."

    message = @server.message_db.new_message
    message.scope = "incoming"
    message.rcpt_to = alias_record.address
    message.mail_from = "reply-bridge-test@example.net"
    message.raw_message = mail.to_s
    message.received_with_ssl = true
    message.reply_bridge_requested = true
    message.reply_bridge_alias_id = alias_record.id
    message.save

    logger = Postal.logger.create_tagged_logger(reply_bridge_test: @server.id)
    MessageDequeuer::IncomingMessageProcessor.process(message.queued_message, logger: logger, state: MessageDequeuer::State.new)
    redirect_to_with_json [:reply_bridge, organization, @server], notice: "Reply Bridge test created an outgoing message for #{current_user.email_address}."
  end

  private

  def safe_params(*extras)
    params.require(:server).permit(:name, :mode, :ip_pool_id, :reply_bridge_mode, :reply_bridge_domain, :reply_bridge_sender, :reply_bridge_alias_ttl_days, *extras)
  end

end
