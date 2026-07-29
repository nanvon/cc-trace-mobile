import 'dart:io';

Future<List<HttpServer>> bindLoopbackServers(int port) async {
  final ipv4 = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    port,
    shared: false,
  );
  final servers = <HttpServer>[ipv4];

  try {
    servers.add(
      await HttpServer.bind(
        InternetAddress.loopbackIPv6,
        ipv4.port,
        shared: false,
        v6Only: true,
      ),
    );
  } on SocketException {
    // IPv6 loopback is an optional compatibility listener. IPv4 remains valid.
  }

  return servers;
}
