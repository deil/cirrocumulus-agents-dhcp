require 'cirrocumulus/ontology'
require File.join(AGENT_ROOT, 'config/ldap_config.rb')
require File.join(AGENT_ROOT, 'ontologies/dhcp_config/subnet.rb')
require File.join(AGENT_ROOT, 'ontologies/dhcp_config/ldap_backend.rb')

class DhcpConfigOntology < Ontology::Base
  def initialize(agent)
    super('cirrocumulus-dhcp', agent)
    @ldap = LdapBackend.new(DHCP_CONFIG)
  end

  def restore_state()

  end

  def handle_message(message, kb)
    case message.act
      when 'query-ref'
        msg = query(message.content)
        msg.receiver = message.sender
        msg.ontology = self.name
        msg.in_reply_to = message.reply_with
        self.agent.send_message(msg)

      when 'request'
        handle_request(message)
    end
  end

  private

  def query(obj)

  end

  def handle_request(message)
    action = message.content.first
    if action == :add
      handle_add_request(message.content, message)
    elsif action == :update
      handle_update_request(message.content.second, message)
    elsif action == :remove
      handle_remove_request(message.content, message)
    end
  end

  # (add (subnet '172.16.11.0') (mac '00:16:...') (ip '172.16.11.101') (hostname 'vuXXX') (network_boot true))
  def handle_add_request(obj, message)
    subnet = mac = ip = hostname = network_boot = nil

    obj.each do |param|
      next if !param.is_a?(Array)

      if param.first == :subnet
        subnet = param.second
      elsif param.first == :mac
        mac = param.second
      elsif param.first == :ip
        ip = param.second
      elsif param.first == :hostname
        hostname = param.second
      elsif param.first == :network_boot
        network_boot = param.second.to_i
      end
    end

    if check_subnet(subnet)
      logger.info "DHCP: #{subnet} ++ (#{mac} = #{ip} [#{hostname}])"
      result = @ldap.add_host(subnet, mac, ip, hostname, network_boot == 1)
      if result
        success(message)
      else
        failure(message)
      end
    else
      refuse(message, :unknown_subnet)
    end
  end

  # (update (subnet '172.16.11.0') (mac '00:16:...') (ip '172.16.11.101') (hostname 'vuYYY') (network_boot false))
  def handle_update_request(obj, message)
    subnet = mac = nil

    obj.each do |param|
      next if !param.is_a?(Array)

      if param.first == :subnet
        subnet = param.second
      elsif param.first == :mac
        mac = param.second
      elsif param.first == :ip
        ip = param.second
      elsif param.first == :hostname
        hostname = param.second
      elsif param.first == :network_boot
        network_boot = param.second.to_i
      end
    end
    
    if check_subnet(subnet)
      logger.info "DHCP: #{subnet} update #{mac}"
      result = false
      if result
        success(message)
      else
        failure(message)
      end
    else
      refuse(message, :uknown_subnet)
    end
  end

  # (remove (subnet '172.16.11.0') (mac '00:16...'))
  def handle_remove_request(obj, message)
    subnet = mac = nil

    obj.each do |param|
      next if !param.is_a?(Array)

      if param.first == :subnet
        subnet = param.second
      elsif param.first == :mac
        mac = param.second
      end
    end
    
    if check_subnet(subnet)
      logger.info "DHCP: #{subnet} -- (#{mac})"
      result = @ldap.remove_host(subnet, mac)
      if result
        success(message)
      else
        failure(message)
      end
    else
      refuse(message, :uknown_subnet)
    end
  end
  
  def check_subnet(subnet)
    return @ldap.list_subnets().collect {|s| s.ip}.include?(subnet)
  end
  
  def refuse(message, reason)
    msg = Cirrocumulus::Message.new(nil, 'refuse', [message.content, [reason]])
    msg.ontology = self.name
    msg.receiver = message.sender
    msg.in_reply_to = message.reply_with
    self.agent.send_message(msg)
  end

  def success(message)
    msg = Cirrocumulus::Message.new(nil, 'inform', [message.content, [:finished]])
    msg.ontology = self.name
    msg.receiver = message.sender
    msg.in_reply_to = message.reply_with
    self.agent.send_message(msg)
  end

  def failure(message)
    msg = Cirrocumulus::Message.new(nil, 'failure', [message.content, [:unknown_reason]])
    msg.ontology = self.name
    msg.receiver = message.sender
    msg.in_reply_to = message.reply_with
    self.agent.send_message(msg)
  end
end
