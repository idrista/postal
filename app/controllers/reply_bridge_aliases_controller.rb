# frozen_string_literal: true

class ReplyBridgeAliasesController < ApplicationController

  include WithinOrganization

  before_action { @server = organization.servers.present.find_by_permalink!(params[:server_id]) }

  def index
    @query = params[:query].to_s.strip
    @aliases = @server.reply_bridge_aliases.order(last_used_at: :desc, created_at: :desc)
    @aliases = @aliases.matching(@query) if @query.present?
    @aliases = @aliases.page(params[:page])
  end

  def destroy
    @server.reply_bridge_aliases.find(params[:id]).destroy
    redirect_to_with_json [organization, @server, :reply_bridge_aliases], notice: "Reply Bridge alias has been deleted."
  end

  def clear_all
    count = @server.reply_bridge_aliases.count
    @server.reply_bridge_aliases.delete_all
    redirect_to_with_json [organization, @server, :reply_bridge_aliases], notice: "#{count} Reply Bridge #{'alias'.pluralize(count)} deleted."
  end

end
