package tink.serialize;

import haxe.macro.Type;
import tink.typecrawler.Generator;
import tink.typecrawler.Crawler;
import tink.typecrawler.FieldInfo;
import haxe.macro.Expr;
import tink.macro.BuildCache;

using haxe.macro.Tools;
using tink.MacroApi;
using tink.CoreApi;

class Encoder<T> {
  final crawler:Crawler;

  function new(crawler)
    this.crawler = crawler;

  public function wrap(placeholder:Expr, ct:ComplexType):Function
    return placeholder.func(['data'.toArg(ct)], false);

  public function nullable(e:Expr):Expr
    return macro
      if (data == null) esc();
      else $e;

  public function string():Expr
    return macro string(data);

  public function float():Expr
    return macro writeFloat(data);

  public function int():Expr
    return macro dynInt(data);

  public function dyn(e:Expr, ct:ComplexType):Expr
    return macro {
      var data:haxe.DynamicAccess<$ct> = value;
      $e;
    }

  public function dynAccess(e:Expr):Expr
    return macro {
      for (k => data in data) {
        string(k);
        $e;
      }
      esc();
    }

  public function bool():Expr
    return macro writeBool(data);

  public function date():Expr
    return macro writeFloat(data.getTime());

  public function bytes():Expr
    return macro writeBytes();

  public function anon(fields:Array<FieldInfo>, ct:ComplexType):Expr
    return [for (f in fields) {
      var name = f.name;
      macro {
        var data = data.$name;
        ${f.expr};
      }
    }].toBlock();

  public function array(e:Expr):Expr
    return macro {
      len(data.length);
      for (data in data) $e;
    }

  public function map(k:Expr, v:Expr):Expr
    return macro {
      for (k => v in data) {
        {
          var data = k;
          $k;
        }
        {
          var data = v;
          $v;
        }
      }
      esc();
    }

  public function enm(constructors:Array<EnumConstructor>, ct:ComplexType, pos:Position, gen:GenType):Expr
    return ESwitch(macro data, [
      for (c in constructors) {
        var ident = macro $i{c.ctor.name},
            idx = macro len($v{c.ctor.index});

        switch c.ctor.type {
          case TFun(args, _):

            function add(args, ret):Case
              return {
                values: [macro $ident($a{args})],
                expr: [idx].concat(ret).toBlock(),
              }

            if (c.inlined) // this distinction is super awkward
              add([macro data], [for (f in c.fields) macro {
                var data = $p{['data', f.name]};
                ${f.expr};
              }]);
            else {
              var args = [for (a in args) a.name];
              var exprs = [for (f in c.fields) f.name => f.expr];
              add([for (a in args) macro $i{a}], [for (a in args) macro {
                var data = $i{a};
                ${exprs[a]};
              }]);
            }
          default:
            {
              values: [ident],
              expr: idx,
            }
        }
      }
    ], null).at();

  public function enumAbstract(names:Array<Expr>, e:Expr, ct:ComplexType, pos:Position):Expr
    return macro @:pos(pos) {
      var data = cast data;
      $e;
    }

  public function rescue(t:Type, pos:Position, gen:GenType):Option<Expr>
    return None;

  public function reject(t:Type):String
    return 'cannot serialize ${t.toString()}';

  public function shouldIncludeField(c:ClassField, owner:Option<ClassType>):Bool
    return Helper.shouldIncludeField(c, owner);

  public function drive(type:Type, pos:Position, gen:GenType):Expr
    return gen(type, pos);

  static function build()
    return BuildCache.getType('tink.serialize.Encoder', null, null, ctx -> {

      var res = Crawler.crawl(ctx.type, ctx.pos, Encoder.new);

      var name = ctx.name;

      var ret = macro class $name extends tink.serialize.Encoder.EncoderBase {
      }

      function addFields(from) {
        ret.fields = ret.fields.concat(from.fields);
        return from.fields;
      }

      addFields(res);
      addFields(macro class {
        public function encode(data) {
          out = new haxe.io.BytesBuffer();
          ${res.expr};
          return out.getBytes();
        }
      });

      ret;
    });
}