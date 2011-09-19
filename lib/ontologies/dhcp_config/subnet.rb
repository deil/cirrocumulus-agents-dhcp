class IP
  attr_reader :ip

  def initialize(ip)
    # The regex isn't perfect but I like it
    if (ip.to_s() =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/)
      @ip = ip
    else
      # Am certain there is a much more elegant way to do this
      octet = []
      octet[0] = (ip & 0xFF000000) >> 24
      octet[1] = (ip & 0x00FF0000) >> 16
      octet[2] = (ip & 0x0000FF00) >> 8
      octet[3] = ip & 0x000000FF
      @ip = octet.join('.')
    end
  end

  def to_i
    # convert ip to 32-bit long (ie: 192.168.0.1 -> 3232235521)
    ip_split = self.ip.split('.')
    long = ip_split[0].to_i() << 24
    long += ip_split[1].to_i() << 16
    long += ip_split[2].to_i() << 8
    long += ip_split[3].to_i()
    # should return long automagically, yeah?
  end

  def to_s
    # This class stores the IP as a string, so we just return it as-is
    @ip
  end

  def bits
    # Count number of bits used (1). This is only really useful for the network mask
    bits = 0
    octets = self.ip.to_s.split('.')
    octets.each { |n|
      #bits += Math.log10(n.to_i + 1) / Math.log10(2) unless n.to_i == 0
      bits += (n.to_i & 0b00000001)
      bits += (n.to_i & 0b00000010) >> 1
      bits += (n.to_i & 0b00000100) >> 2
      bits += (n.to_i & 0b00001000) >> 3
      bits += (n.to_i & 0b00010000) >> 4
      bits += (n.to_i & 0b00100000) >> 5
      bits += (n.to_i & 0b01000000) >> 6
      bits += (n.to_i & 0b10000000) >> 7
    }

    bits
  end
end

class AddressInfo
  attr_reader :ip, :netmask

  def initialize(ip, netmask)
    @ip = ip
    @netmask = netmask
  end

  def subnet
    @subnet ||= IP.new(ip.to_i & netmask.to_i)
  end

  def broadcast
    @broadcast ||= IP.new(self.subnet().to_i | ~@netmask.to_i)
  end

  def router
    IP.new(subnet.to_i + 1)
  end

  def range
    "%s %s" % [IP.new(router.to_i + 99), IP.new(broadcast.to_i - 1)]
  end

  def maxhosts
    @maxhosts ||= self.broadcast.to_i - self.subnet.to_i - 2
  end
end
