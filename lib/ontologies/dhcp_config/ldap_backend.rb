require 'ldap'

class LdapBackend
  def initialize(config)
    @config = config
  end

  def list_subnets()
    self.connect do |ldap|
      result = []
      ldap.search("cn=DHCPConfig,%s" % @config[:base_dn], LDAP::LDAP_SCOPE_ONELEVEL, "(objectClass=dhcpSubnet)") do |entry|
        result << AddressInfo.new(entry['cn'].first, entry['dhcpNetMask'].first.to_i)
      end
      
      return result
    end
  rescue Exception => ex
    []
  end

  def add_subnet(subnet, netmask)
    ldap = LdapBackend.open()
    addr = AddressInfo.new(IP.new(subnet), IP.new(netmask))

    cn = addr.subnet.to_s
    dn = "cn=#{cn},cn=DHCPConfig,#{LDAP_BASE_DN}"
    attr = [
      LDAP::Mod.new(LDAP::LDAP_MOD_ADD, 'cn', [cn]),
      LDAP::Mod.new(LDAP::LDAP_MOD_ADD, 'objectClass', ['top', 'dhcpSubnet', 'dhcpOptions']),
      LDAP::Mod.new(LDAP::LDAP_MOD_ADD, 'dhcpNetMask', [addr.netmask.bits.to_s]),
      LDAP::Mod.new(LDAP::LDAP_MOD_ADD, 'dhcpOption', ["routers %s" % [addr.router.to_s]]),
      LDAP::Mod.new(LDAP::LDAP_MOD_ADD, 'dhcpRange', [addr.range]),
    ]

    ldap.add(dn, attr)
    ldap.unbind
  end

  def list_hosts(subnet)
    self.connect do |ldap|
      result = []
      ldap.search("cn=%s,cn=DHCPConfig,%s" % [subnet, @config[:base_dn]], LDAP::LDAP_SCOPE_ONELEVEL, "(objectClass=dhcpHost)") do |entry|
        hash = Hash.new
        hash[:host] = entry['cn'][0]
        hash[:mac] = entry['dhcpHWAddress'][0].split(' ')[1]
        entry['dhcpStatements'].each do |statement|
          slices = statement.split(' ')
          if slices[0] == 'fixed-address'
            hash[:ip] = slices[1]
          end
        end

        result << hash
      end

      return result
    end
  end

  def add_host(subnet, mac, ip, hostname, network_boot)
    self.connect do |ldap|
      dn = "cn=%s,cn=%s,cn=DHCPConfig,%s" % [hostname, subnet, @config[:base_dn]]
      attr = [
        LDAP::Mod.new(LDAP::LDAP_MOD_ADD, 'cn', [hostname]),
        LDAP::Mod.new(LDAP::LDAP_MOD_ADD, 'objectClass', ['top', 'dhcpHost', 'dhcpOptions']),
        LDAP::Mod.new(LDAP::LDAP_MOD_ADD, 'dhcpHWAddress', ["ethernet #{mac}"]),
        LDAP::Mod.new(LDAP::LDAP_MOD_ADD, 'dhcpStatements', ["fixed-address #{ip}"]),
        LDAP::Mod.new(LDAP::LDAP_MOD_ADD, 'dhcpOption', ["host-name \"#{hostname}\""]),
      ]

      return ldap.add(dn, attr)
    end
  rescue
    false
  end

  def get_host(subnet, mac)
    self.connect do |ldap|
      ldap.search("cn=%s,cn=DHCPConfig,%s" % [subnet, @config[:base_dn]], LDAP::LDAP_SCOPE_ONELEVEL, "(objectClass=dhcpHost)") do |entry|
        hw_addr = entry['dhcpHWAddress'].first.split(' ')[1]
        if hw_addr == mac
          fixed_address = nil
          network_boot = 0
          entry['dhcpStatements'].each do |s|
            slices = s.split(' ')
            fixed_address = slices[1] if slices.first == 'fixed-address'
            network_boot = 1 if ['next-server', 'filename'].include? slices.first
          end

          return {
            :host => entry['cn'].first,
            :mac => hw_addr,
            :ip => fixed_address,
            :network_boot => network_boot
          }
        end
      end
    end
    
    nil
  rescue Exception => ex
    puts ex.to_s
    nil
  end

  
  def update_host(subnet, mac, ip, hostname, network_boot)
    old = get_host(subnet, mac)

    self.connect do |ldap|
      if !ip.empty? && ip != old[:ip]
        mods = ['fixed-address ' + ip]
        if old[:network_boot] == 1
          mods << 'next-server 172.16.11.2'
          mods << 'filename "pxelinux.0"'
        end
        ip_mod = [LDAP.mod(LDAP::LDAP_MOD_REPLACE, 'dhcpStatements', mods)]
        ldap.modify("cn=%s,cn=%s,cn=DHCPConfig,%s" % [old[:host], subnet, @config[:base_dn]], ip_mod)
      end

      if !network_boot.nil? && network_boot != old[:network_boot]
        if network_boot == 1
          boot_mod = [LDAP.mod(LDAP::LDAP_MOD_ADD, 'dhcpStatements', ['next-server 172.16.11.2', 'filename "pxelinux.0"'])]
          ldap.modify("cn=%s,cn=%s,cn=DHCPConfig,%s" % [old[:host], subnet, @config[:base_dn]], boot_mod)
        elsif network_boot == 0
          no_boot_mod = [LDAP.mod(LDAP::LDAP_MOD_DELETE, 'dhcpStatements', ['next-server 172.16.11.2', 'filename "pxelinux.0"'])]
          ldap.modify("cn=%s,cn=%s,cn=DHCPConfig,%s" % [old[:host], subnet, @config[:base_dn]], no_boot_mod)
        end
      end

      if !hostname.empty? && hostname != old[:host]
        host_mod = [LDAP.mod(LDAP::LDAP_MOD_REPLACE, 'dhcpOption', ["host-name \"#{hostname}\""])]
        ldap.modify("cn=%s,cn=%s,cn=DHCPConfig,%s" % [old[:host], subnet, @config[:base_dn]], host_mod)
        ldap.modrdn(
          "cn=%s,cn=%s,cn=DHCPConfig,%s" % [old[:host], subnet, @config[:base_dn]],
          "cn=%s" % [hostname],
          true
        )
      end
    end
    
    true
  rescue Exception => ex
    puts ex.to_s
    false
  end

  def remove_host(subnet, mac)
    self.connect do |ldap|
      ldap.search("cn=#{subnet},cn=DHCPConfig,#{@config[:base_dn]}", LDAP::LDAP_SCOPE_ONELEVEL, "(objectClass=dhcpHost)") do |entry|
        entry_mac = entry['dhcpHWAddress'][0].split(' ')[1]
        if entry_mac == mac
          return ldap.delete(entry.dn)
        end
      end
    end

    false
  rescue
    false
  end

  def request_ip(subnet)
    used = list_hosts(subnet)
    used.sort! {|a,b| IP.new(a[:ip]).to_i <=> IP.new(b[:ip]).to_i}
    last_ip = IP.new(used.last[:ip])
    requested_ip = IP.new(last_ip.to_i + 1)
    requested_ip.to_s
  end

  def assign_private_ip(mac, hostname)
    ip = request_ip('172.16.12.0')
    add_host('172.16.12.0', mac, ip, hostname, false)
    ip
  end

  def assign_public_ip(mac)
    '89.223.109.1'
  end

  protected

  def connect(&block)
    conn = LDAP::Conn.new(@config[:host], @config[:port])
    conn.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    conn.bind(@config[:user], @config[:password])

    block.call(conn)

    conn.unbind()
  end
end
