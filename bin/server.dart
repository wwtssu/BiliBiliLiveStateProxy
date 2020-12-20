import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:dio/dio.dart';
const _hostname = '0.0.0.0';
main(List<String> args) async {
  var parser = ArgParser()..addOption('port', abbr: 'p');
  var result = parser.parse(args);
  var portStr = result['port'] ?? Platform.environment['PORT'] ?? '16000';
  var port = int.tryParse(portStr);

  if (port == null) {
    exitCode = 64;
    return;
  }

  var handler = Router();
  
  handler.all('/<.*>', _notFound);

  handler.get('/get_status_info_by_uid/<uid>',_get_status_info_by_uid);
  

  var server = await io.serve(handler, _hostname, port);
  print('Serving at http://${server.address.host}:${server.port}');
  refreshTimer = Timer.periodic(Duration(seconds: 30), (_){
    refreshInfo();
  });
}

Timer refreshTimer;

List<Info> infoList = [];

class Info{
  int uid;
  dynamic data;
  DateTime lastFetch;
  bool isError = false;
  @override
  String toString() {
    return '$uid-${data != null ? data['uname'] : 'unknown'}';
  }
}

void refreshInfo() async{
  infoList.removeWhere((element) {
    if(DateTime.now().difference(element.lastFetch).inSeconds > 120){
      print('${element.uid}-${element.data != null ? element.data['uname'] : 'unknown'} is removed.');
      return true;
    }
    else {
      return false;
    }
  });
  var shouldRefreshList = infoList.where((element) => !element.isError).toList();
  if(shouldRefreshList.isNotEmpty){
    print('------------------refresh start------------------');
    var count = shouldRefreshList.length;
    print('count = $count');
    var oneQureyCount = 200;
    while(count > 0){
      var url = "https://api.live.bilibili.com/room/v1/Room/get_status_info_by_uids?uids[]=${(shouldRefreshList.skip(shouldRefreshList.length - count)).take(oneQureyCount).map((e) => e.uid).toList().join('&uids[]=')}";
      print('request url: $url');
      var response = await Dio().get(url);
      var json = response.data;
      if(json['code'] == 0){
        count = count - oneQureyCount;
        if(json['data'] is Map) {
            json['data'].forEach((k,v){
              var info = getInfo(int.parse(k));
              info.data = v;
              print("update: index = ${infoList.indexOf(info)}, uid = $k, uname = ${v['uname']}, timeout = ${DateTime.now().difference(info.lastFetch).inSeconds}");
            }
          );
        }
      }
    }
    infoList.forEach((element) {
      if(element.data == null) element.isError = true;
    });
    print('-------------------refresh end-------------------');
  }
}

bool containsUid(int uid){
  var isContains = false;
  infoList.forEach((element) {
    if(element.uid == uid) isContains = true;
  });
  return isContains;
}

Info getInfo(uid){
  var info;
  infoList.forEach((element) {
    if(element.uid == uid) info = element;
  });
  return info;
}

Future<shelf.Response> _get_status_info_by_uid(shelf.Request request, String uid_s) async{
   return request.readAsString().then((String body) async{
      var uid = int.parse(uid_s);
      if(!containsUid(uid)){
        infoList.add(Info()..uid = uid..lastFetch = DateTime.now());
      }
      var info = getInfo(uid);
      if(info.isError){
        if(DateTime.now().difference(info.lastFetch).inSeconds < 3600){
          print('request: uid = $uid, data = ${json.encode(info.data)}');
          return null;
        }else{
          info.isError = false;
          info.lastFetch = DateTime.now();
        }
      }
      if(info.data == null){
        await refreshInfo();
      }
      info.lastFetch = DateTime.now();
      print('request: uid = $uid, data = ${json.encode(info.data)}');
      return info.data;
    }).then((data){
      if(data != null){
        var ret = {
          'code': 0,
          'message': 'OK',
          'data': data,
        };
        return Future.sync(() => shelf.Response.ok(json.encode(ret),headers: {'Content-Type':'application/json;charset=UTF-8','Access-Control-Allow-Origin':'*'}));
      }
      return Future.sync(() => shelf.Response.forbidden(json.encode({'code':-1,'msg':'获取错误！'}),headers: {'Content-Type':'application/json;charset=UTF-8','Access-Control-Allow-Origin':'*'}));
    });
}


Future<shelf.Response> _notFound(shelf.Request request) {
  return request.readAsString().then((String body) {
    //var requestBody = json.decode(body);
    return Future.sync(() => shelf.Response.notFound(json.encode({'code':404,'msg':'访问错误！'}),headers: {'Content-Type':'application/json;charset=UTF-8','Access-Control-Allow-Origin':'*'}));
  });
}