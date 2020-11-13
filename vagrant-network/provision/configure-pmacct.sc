// configure pmacct
// cf. https://opennms.discourse.group/t/how-to-use-pmacct-as-a-netflow-9-probe-on-ubuntu-linux

import ammonite.ops._
import ammonite.ops.ImplicitWd._

try {
  val boxStaticIp = sys.env("VAGRANT_BOX_STATIC_IP")
  val onmsIp = sys.env("OPENNMS_IP")
  val onmsNetflowPort = sys.env("OPENNMS_NETFLOW_PORT")

  val lines: Vector[String] = %%("ip", "address", "show").out.lines
  // look for those 6 lines that contain the boxStaticIp in the 3rd line
  val vec = lines.grouped(6).find(v => v(2).contains(boxStaticIp)).get

  // match the first and second line of the found block of lines with regular expressions
  // -> extract the interface number / name and mac address
  val Line0 = """(\d+):\s+([^:]+):.*""".r
  val Line1 = """\s+link/ether\s+(\S+).*""".r

  val Line0(interfaceNumber, interfaceName) = vec(0)
  val Line1(macAddress) = vec(1)

  println(s"interfaceNumber: $interfaceNumber")
  println(s"interfaceName  : $interfaceName")
  println(s"MAC address    : $macAddress")

  val pmacctdConf =
    s"""
      |daemonize: true
      |interface: $interfaceName
      |aggregate: src_host, dst_host, src_port, dst_port, proto, tos
      |plugins: nfprobe[$interfaceName]
      |nfprobe_receiver: $onmsIp:$onmsNetflowPort
      |nfprobe_version: 9
      |nfprobe_direction[$interfaceName]: tag
      |nfprobe_ifindex[$interfaceName]: tag2
      |pre_tag_map: /etc/pmacct/pretag.map
      |timestamps_secs: true
      |plugin_buffer_size: 1000
      |""".stripMargin

  val pretagMap =
    s"""
      |# Use a filter to determine direction
      |# Set 1 for ingress and 2 for egress
      |#
      |# Local MAC
      |set_tag=1 filter='ether dst $macAddress' jeq=eval_ifindexes
      |set_tag=2 filter='ether src $macAddress' jeq=eval_ifindexes
      |
      |# Use a filter to set the ifindexes
      |set_tag2=2 filter='ether src $macAddress' label=eval_ifindexes
      |set_tag2=2 filter='ether dst $macAddress'
      |""".stripMargin

  write.over(root/"etc"/"pmacct"/"pmacctd.conf", pmacctdConf)
  write.over(root/"etc"/"pmacct"/"pretag.map", pretagMap)

} catch {
  case t => t.printStackTrace()
    throw t
}
