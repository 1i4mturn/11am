# The brand's line glyphs (24-point square, 1.5pt ink, round ends), defined once: this writes the Swift and a contact sheet.
# python3 tools/glyphs.py swift Shared/IconsMore.swift    then    python3 tools/glyphs.py png sheet.png  (needs Pillow)
import math, sys
G = {}
class Pen:
    def __init__(s): s.ops = []
    def line(s, pts, closed=False): s.ops.append(('line', [tuple(map(float, p)) for p in pts], closed))
    def box(s, x, y, w, h): s.ops.append(('box', x, y, w, h))
    def circle(s, x, y, r): s.ops.append(('circle', x, y, r))
    def ellipse(s, x, y, w, h): s.ops.append(('ellipse', x, y, w, h))
    def rrect(s, x, y, w, h, r): s.ops.append(('rrect', x, y, w, h, r))
    def arc(s, cx, cy, r, a, b, start=True): s.ops.append(('arc', cx, cy, r, a, b, start))
    def move(s, x, y): s.ops.append(('move', x, y))
    def quad(s, x, y, cx, cy): s.ops.append(('quad', x, y, cx, cy))
    def close(s): s.ops.append(('close',))
def glyph(*names):
    def deco(f):
        for n in names: G[n] = f
        return f
    return deco
# shared parts
def page(p): p.line([(6,3),(14,3),(19,8),(19,21),(6,21)], True); p.line([(14,3),(14,8),(19,8)])
def speaker(p): p.line([(3,9.5),(7,9.5),(11.5,5.5),(11.5,18.5),(7,14.5),(3,14.5)], True)
def cloud(p, y=0):
    p.arc(8,13+y,3.5,90,270); p.arc(12.5,9.5+y,5,200,340,False); p.arc(17,13+y,3.5,270,450,False); p.line([(17,16.5+y),(8,16.5+y)])
def lens(p, cx=10.5, cy=10.5, r=6.5): p.circle(cx,cy,r); k=r/math.sqrt(2); p.line([(cx+k+0.3,cy+k+0.3),(cx+r+4,cy+r+4)])
def personc(p, cx, cy, r): p.circle(cx,cy-r*0.22,r*0.33); p.arc(cx,cy+r*0.98,r*0.7,200,340)
def check(p, x=0, y=0, s=1): p.line([(8*s+x,12.5*s+y),(11*s+x,15.5*s+y),(16.5*s+x,9*s+y)])
def bell(p):
    p.line([(5,17),(19,17)]); p.line([(6.5,17),(6.5,11)]); p.arc(12,11,5.5,180,360,False); p.line([(17.5,11),(17.5,17)]); p.line([(10,20.5),(14,20.5)])
def slider_h(p, knobs):
    for y,k in zip((6,12,18), knobs):
        p.line([(3,y),(k-2,y)]); p.circle(k,y,2); p.line([(k+2,y),(21,y)])

@glyph('paperclip')
def _(p):
    p.move(15.5,8); p.line([(15.5,8),(15.5,16)]); p.arc(12,16,3.5,0,180,False); p.line([(8.5,16),(8.5,6)]); p.arc(11.5,6,3,180,360,False)
    p.line([(14.5,6),(14.5,15)]); p.arc(12.5,15,2,0,180,False); p.line([(10.5,15),(10.5,8)])
@glyph('slider.horizontal.3')
def _(p): slider_h(p, (8,16,11))
@glyph('slider.vertical.3')
def _(p):
    for x,k in zip((6,12,18),(10,16,7)):
        p.line([(x,3),(x,k-2)]); p.circle(x,k,2); p.line([(x,k+2),(x,21)])
@glyph('speaker')
def _(p): speaker(p)
@glyph('speaker.wave.1')
def _(p): speaker(p); p.arc(12.5,12,4,-45,45)
@glyph('speaker.wave.2')
def _(p): speaker(p); p.arc(12.5,12,4,-45,45); p.arc(12.5,12,7.5,-45,45)
@glyph('speaker.slash')
def _(p): speaker(p); p.line([(3,3),(21,21)])
@glyph('rectangle.stack')
def _(p): p.box(3,9,18,12); p.line([(5,6),(19,6)]); p.line([(7,3),(17,3)])
@glyph('arrow.up.circle')
def _(p): p.circle(12,12,9); p.line([(12,16.5),(12,7.5)]); p.line([(8.5,11),(12,7.5),(15.5,11)])
@glyph('arrow.down.circle')
def _(p): p.circle(12,12,9); p.line([(12,7.5),(12,16.5)]); p.line([(8.5,13),(12,16.5),(15.5,13)])
@glyph('arrow.right.circle')
def _(p): p.circle(12,12,9); p.line([(7.5,12),(16.5,12)]); p.line([(13,8.5),(16.5,12),(13,15.5)])
@glyph('chevron.down.circle')
def _(p): p.circle(12,12,9); p.line([(7.5,10.5),(12,15),(16.5,10.5)])
@glyph('questionmark.circle')
def _(p): p.circle(12,12,9); p.arc(12,9.8,3,200,390); p.line([(14.8,10.8),(12,13),(12,14.5)]); p.circle(12,17.3,0.5)
@glyph('doc.badge.plus')
def _(p): page(p); p.line([(12.5,11),(12.5,18)]); p.line([(9,14.5),(16,14.5)])
@glyph('doc.richtext')
def _(p): page(p); p.line([(9,12),(16,12)]); p.line([(9,18),(11.5,15.5),(13.5,17),(16,14.5)])
@glyph('doc.plaintext')
def _(p): page(p); p.line([(9,11),(16,11)]); p.line([(9,14.5),(16,14.5)]); p.line([(9,18),(13,18)])
@glyph('doc.text.magnifyingglass')
def _(p): p.line([(13,21),(5,21),(5,3),(13,3),(18,8),(18,10)]); p.line([(13,3),(13,8),(18,8)]); lens(p,14.5,15,3.5)
@glyph('doc.zipper')
def _(p): page(p); p.line([(10,5),(10,6)]); p.line([(10,8),(10,9)]); p.line([(10,11),(10,12)]); p.box(8.5,14,3,4)
@glyph('iphone')
def _(p): p.rrect(7,2.5,10,19,2.5); p.line([(10.5,5),(13.5,5)])
@glyph('iphone.and.arrow.forward')
def _(p): p.rrect(3,2.5,9,19,2.5); p.line([(14,12),(21,12)]); p.line([(18,9),(21,12),(18,15)])
@glyph('laptopcomputer')
def _(p): p.box(5,4.5,14,10.5); p.line([(2.5,18.5),(21.5,18.5)]); p.line([(5,15),(3,18.5)]); p.line([(19,15),(21,18.5)])
@glyph('text.quote')
def _(p): p.line([(4,5),(4,19)]); p.line([(8,6),(20,6)]); p.line([(8,12),(20,12)]); p.line([(8,18),(16,18)])
@glyph('square.and.pencil')
def _(p): p.line([(11,4),(4,4),(4,20),(20,20),(20,13)]); p.line([(17.5,3),(21,6.5),(13,14.5),(9.5,14.5),(9.5,11)], True)
@glyph('person.crop.circle')
def _(p): p.circle(12,12,9); personc(p,12,12,8)
@glyph('person.crop.circle.badge.plus')
def _(p): p.circle(11,13,8); personc(p,11,13,7); p.line([(19.5,1.5),(19.5,7.5)]); p.line([(16.5,4.5),(22.5,4.5)])
@glyph('person.crop.circle.badge.minus')
def _(p): p.circle(11,13,8); personc(p,11,13,7); p.line([(16.5,4.5),(22.5,4.5)])
@glyph('person.crop.rectangle')
def _(p): p.box(3,4,18,16); p.circle(12,10,3); p.arc(12,20,5.5,180,360)
@glyph('person.text.rectangle')
def _(p): p.box(2.5,4,19,16); p.circle(8,10,2.5); p.arc(8,18.5,4.5,180,360); p.line([(14,9),(19,9)]); p.line([(14,13),(19,13)])
@glyph('person.3')
def _(p): p.circle(12,7.5,3); p.arc(12,18,5.5,180,360); p.circle(5.5,9.5,2.3); p.arc(5.5,18,4,200,330); p.circle(18.5,9.5,2.3); p.arc(18.5,18,4,210,340)
@glyph('person.wave.2')
def _(p): p.circle(12,8,3.5); p.arc(12,21,7,180,360); p.arc(12,9,8,140,220); p.arc(12,9,8,-40,40)
@glyph('circle.lefthalf.filled')
def _(p): p.circle(12,12,9); p.line([(12,3),(12,21)]); p.line([(6,7.5),(12,7.5)]); p.line([(3.5,12),(12,12)]); p.line([(6,16.5),(12,16.5)])
@glyph('circle.dashed')
def _(p):
    for k in range(12): p.arc(12,12,9,k*30+6,k*30+20)
@glyph('circle.dotted')
def _(p):
    for k in range(12):
        a=math.radians(k*30); p.circle(12+9*math.cos(a),12+9*math.sin(a),0.4)
@glyph('rectangle.split.2x1')
def _(p): p.box(3,5,18,14); p.line([(12,5),(12,19)])
@glyph('rectangle.split.1x2')
def _(p): p.box(3,4,18,16); p.line([(3,12),(21,12)])
@glyph('rectangle.split.2x2')
def _(p): p.box(3,4,18,16); p.line([(12,4),(12,20)]); p.line([(3,12),(21,12)])
@glyph('rectangle.split.3x1')
def _(p): p.box(3,5,18,14); p.line([(9,5),(9,19)]); p.line([(15,5),(15,19)])
@glyph('rectangle')
def _(p): p.box(3,6,18,12)
@glyph('rectangle.on.rectangle')
def _(p): p.line([(3,16),(3,4),(17,4)]); p.box(7,8,14,12)
@glyph('rectangle.on.rectangle.angled')
def _(p): p.line([(4,15),(2.5,6),(16,3.5)]); p.line([(7,8),(20,7),(21,18),(8,19)], True)
@glyph('plus.rectangle.on.rectangle')
def _(p): p.line([(3,16),(3,4),(16,4)]); p.box(7,8,14,12); p.line([(14,11),(14,17)]); p.line([(11,14),(17,14)])
@glyph('rectangle.3.group')
def _(p): p.box(3,4,8,7); p.box(13,4,8,7); p.box(3,13,18,7)
@glyph('rectangle.bottomhalf.inset.filled')
def _(p): p.box(3,4,18,16); p.box(6,13,12,4)
@glyph('books.vertical')
def _(p): p.box(3,4,4,16); p.box(9,4,4,16); p.line([(15.2,5),(18.8,4.2),(21.8,19.4),(18.2,20.2)], True)
@glyph('book')
def _(p):
    p.line([(12,6),(12,20)]); p.line([(12,6),(8,4.5),(3,5),(3,19),(8,18.5),(12,20)]); p.line([(12,6),(16,4.5),(21,5),(21,19),(16,18.5),(12,20)])
@glyph('book.closed', 'text.book.closed')
def _(p): p.line([(6,21),(6,3),(19,3),(19,21),(6,21)]); p.line([(9,3),(9,21)]); p.line([(12,8),(16,8)])
@glyph('bookmark')
def _(p): p.line([(6,3),(18,3),(18,21),(12,16),(6,21)], True)
@glyph('video')
def _(p): p.box(3,7,12.5,10); p.line([(15.5,10.5),(21,7.5),(21,16.5),(15.5,13.5)])
@glyph('mappin.and.ellipse')
def _(p): p.circle(12,8,4.5); p.line([(12,12.5),(12,18)]); p.ellipse(5,16.5,14,5)
@glyph('car')
def _(p): p.line([(3,16),(3,12),(6.5,7),(17.5,7),(21,12),(21,16),(3,16)]); p.line([(3,12),(21,12)]); p.circle(7.5,16.5,1.8); p.circle(16.5,16.5,1.8)
@glyph('timer')
def _(p): p.circle(12,13,8); p.line([(12,13),(15.5,9.5)]); p.line([(12,2.5),(12,5)]); p.line([(10,2.5),(14,2.5)]); p.line([(18.5,5),(20,6.5)])
@glyph('clock.badge.checkmark')
def _(p): p.circle(11,13,7.5); p.line([(11,9),(11,13),(14,15)]); p.line([(16,4.5),(18,6.5),(22,2.5)])
@glyph('clock.arrow.circlepath')
def _(p): p.arc(12,12,8.5,200,500); p.line([(2,6.5),(4,9.1),(6.8,7.6)]); p.line([(12,7.5),(12,12),(15,14)])
@glyph('line.3.horizontal.decrease')
def _(p): p.line([(4,7),(20,7)]); p.line([(7,12),(17,12)]); p.line([(10,17),(14,17)])
@glyph('line.3.horizontal.decrease.circle')
def _(p): p.circle(12,12,9); p.line([(7,9),(17,9)]); p.line([(9,12.5),(15,12.5)]); p.line([(11,16),(13,16)])
@glyph('calendar.badge.plus')
def _(p): p.box(3,5,18,16); p.line([(3,10),(21,10)]); p.line([(8,3),(8,7)]); p.line([(16,3),(16,7)]); p.line([(12,12.5),(12,18.5)]); p.line([(9,15.5),(15,15.5)])
@glyph('calendar.day.timeline.left')
def _(p): p.box(3,4,18,16); p.line([(8,4),(8,20)]); p.line([(11,9),(18,9)]); p.line([(11,14),(16,14)])
@glyph('return')
def _(p): p.line([(19,5),(19,13),(6,13)]); p.line([(10,9),(6,13),(10,17)])
@glyph('lightbulb')
def _(p): p.arc(12,9.5,6,140,400); p.line([(16.6,13.4),(15,16),(9,16),(7.4,13.4)]); p.line([(9.5,19),(14.5,19)]); p.line([(10.5,21.5),(13.5,21.5)])
@glyph('checkmark.seal')
def _(p):
    pts=[]
    for k in range(24):
        a=math.radians(k*15); r=9.5 if k%2==0 else 8.2; pts.append((round(12+r*math.cos(a),2), round(12+r*math.sin(a),2)))
    p.line(pts, True); check(p)
@glyph('checkmark.square')
def _(p): p.box(4,4,16,16); p.line([(8,12.5),(11,15.5),(16,9)])
@glyph('tortoise')
def _(p): p.arc(11,15,7,180,360); p.line([(4,15),(18,15)]); p.circle(20,13,1.8); p.line([(7,15),(6,18.5)]); p.line([(15,15),(16,18.5)]); p.line([(8,11),(14,11)])
@glyph('sum')
def _(p): p.line([(18,4),(6,4),(13,12),(6,20),(18,20)])
@glyph('number')
def _(p): p.line([(9,4),(7,20)]); p.line([(17,4),(15,20)]); p.line([(4.5,9),(20,9)]); p.line([(4,15),(19.5,15)])
@glyph('list.number')
def _(p):
    p.line([(4,4.5),(5,4),(5,9)]); p.line([(3.5,13.5),(6,13.5),(3.5,17.5),(6.5,17.5)])
    p.line([(10,7),(20,7)]); p.line([(10,15.5),(20,15.5)])
@glyph('chart.bar.xaxis')
def _(p): p.line([(3,20),(21,20)]); p.box(5.5,12,3,6); p.box(10.5,6,3,12); p.box(15.5,9,3,9)
@glyph('chart.line.uptrend.xyaxis')
def _(p): p.line([(3,3),(3,21),(21,21)]); p.line([(6,16),(10,11),(13,14),(20,6)]); p.line([(16,6),(20,6),(20,10)])
@glyph('chart.bar.doc.horizontal')
def _(p): page(p); p.line([(9,11),(15,11)]); p.line([(9,14.5),(13,14.5)]); p.line([(9,18),(16,18)])
@glyph('building.columns')
def _(p):
    p.line([(3,9),(12,3.5),(21,9)], True); p.line([(3,20.5),(21,20.5)])
    for x in (6,10,14,18): p.line([(x,11.5),(x,18)])
@glyph('paintpalette')
def _(p):
    p.arc(12,12,9,30,320); p.quad(15.5,16,19.5,8); p.quad(19.8,19,13,19.5)
    for x,y in ((8,9),(12,6.5),(16,8.5),(7.5,14)): p.circle(x,y,1.3)
@glyph('paintbrush')
def _(p): p.line([(20,3),(10,13)]); p.line([(21,4),(11,14)]); p.line([(9.5,13),(11,14.5)]); p.quad(3,20,9,19); p.line([(3,20),(5,15),(9.5,13)])
@glyph('paintbrush.pointed')
def _(p): p.line([(20,4),(11,14),(9,12),(19,3)], True); p.line([(9,12),(5,13),(3,21),(11,19),(11,14)])
@glyph('eye.slash')
def _(p): p.move(2,12); p.quad(22,12,12,2); p.quad(2,12,12,22); p.circle(12,12,3); p.line([(4,4),(20,20)])
@glyph('text.bubble')
def _(p): p.line([(3,4),(21,4),(21,16),(10,16),(5,20),(5,16),(3,16)], True); p.line([(7,8.5),(17,8.5)]); p.line([(7,12),(14,12)])
@glyph('quote.bubble')
def _(p): p.line([(3,4),(21,4),(21,16),(10,16),(5,20),(5,16),(3,16)], True); p.line([(9,8),(8,12)]); p.line([(13,8),(12,12)])
@glyph('quote.opening')
def _(p): p.circle(7.5,13,2.5); p.arc(9,13,4,180,250); p.circle(15.5,13,2.5); p.arc(17,13,4,180,250)
@glyph('rotate.right')
def _(p): p.box(4,11,10,10); p.arc(12,11,7,220,330); p.line([(18.5,3.8),(18.06,7.5),(14.5,6.8)])
@glyph('rotate.left')
def _(p): p.box(10,11,10,10); p.arc(12,11,7,210,320); p.line([(5.5,3.8),(5.94,7.5),(9.5,6.8)])
@glyph('arrow.left.and.right.righttriangle.left.righttriangle.right')
def _(p): p.line([(10,6),(10,18),(3,18)], True); p.line([(14,6),(14,18),(21,18)], True); p.line([(12,3),(12,21)])
@glyph('arrow.up.and.down.righttriangle.up.righttriangle.down')
def _(p): p.line([(6,10),(18,10),(18,3)], True); p.line([(6,14),(18,14),(18,21)], True); p.line([(3,12),(21,12)])
@glyph('sidebar.left')
def _(p): p.box(3,4,18,16); p.line([(9,4),(9,20)]); p.line([(5,7.5),(7,7.5)]); p.line([(5,10.5),(7,10.5)])
@glyph('sidebar.right')
def _(p): p.box(3,4,18,16); p.line([(15,4),(15,20)]); p.line([(17,7.5),(19,7.5)]); p.line([(17,10.5),(19,10.5)])
@glyph('menubar.dock.rectangle')
def _(p): p.box(3,4,18,16); p.line([(3,7.5),(21,7.5)]); p.box(7,16,10,2)
@glyph('location')
def _(p): p.line([(20,4),(4,11),(11,13),(13,20)], True)
@glyph('briefcase')
def _(p): p.box(3,7,18,13); p.line([(9,7),(9,4),(15,4),(15,7)]); p.line([(3,12.5),(21,12.5)])
@glyph('cpu')
def _(p):
    p.box(6,6,12,12); p.box(9.5,9.5,5,5)
    for v in (9,12,15): p.line([(v,3),(v,6)]); p.line([(v,18),(v,21)]); p.line([(3,v),(6,v)]); p.line([(18,v),(21,v)])
@glyph('pin')
def _(p): p.line([(9,3),(15,3)]); p.line([(10,3),(10,9),(7,13),(17,13),(14,9),(14,3)]); p.line([(12,13),(12,21)])
@glyph('dot.radiowaves.left.and.right')
def _(p): p.circle(12,12,1.5); p.arc(12,12,5,-40,40); p.arc(12,12,5,140,220); p.arc(12,12,8.5,-40,40); p.arc(12,12,8.5,140,220)
@glyph('textformat')
def _(p): p.line([(3,19),(8,5),(13,19)]); p.line([(5,14),(11,14)]); p.circle(17.5,15.5,3); p.line([(20.5,12),(20.5,19)])
@glyph('textformat.size', 'textformat.size.larger')
def _(p): p.line([(2,19),(8,4),(14,19)]); p.line([(4.5,13.5),(11.5,13.5)]); p.line([(14,19),(17.5,10),(21,19)]); p.line([(15.3,16),(19.7,16)])
@glyph('bold')
def _(p): p.line([(7,4),(7,20)]); p.line([(7,4),(13,4)]); p.arc(13,8,4,270,450,False); p.line([(13,12),(7,12)]); p.line([(7,12),(14,12)]); p.arc(14,16,4,270,450,False); p.line([(14,20),(7,20)])
@glyph('italic')
def _(p): p.line([(10,4),(18,4)]); p.line([(6,20),(14,20)]); p.line([(14,4),(10,20)])
@glyph('underline')
def _(p): p.line([(7,4),(7,12)]); p.arc(12,12,5,180,0,False); p.line([(17,12),(17,4)]); p.line([(5,20.5),(19,20.5)])
@glyph('strikethrough')
def _(p): p.arc(12,8,4.5,0,-270); p.arc(12,16,4.5,270,450); p.line([(12,20.5),(7.5,18)]); p.line([(3,12),(21,12)])
@glyph('text.alignleft')
def _(p): p.line([(3,5),(21,5)]); p.line([(3,10),(15,10)]); p.line([(3,15),(21,15)]); p.line([(3,20),(13,20)])
@glyph('text.aligncenter')
def _(p): p.line([(3,5),(21,5)]); p.line([(6,10),(18,10)]); p.line([(3,15),(21,15)]); p.line([(7,20),(17,20)])
@glyph('text.alignright')
def _(p): p.line([(3,5),(21,5)]); p.line([(9,10),(21,10)]); p.line([(3,15),(21,15)]); p.line([(11,20),(21,20)])
@glyph('text.append')
def _(p): p.line([(3,5),(21,5)]); p.line([(3,10),(21,10)]); p.line([(3,15),(12,15)]); p.line([(17,13),(17,21)]); p.line([(13,17),(21,17)])
@glyph('text.badge.plus')
def _(p): p.line([(3,6),(14,6)]); p.line([(3,11),(14,11)]); p.line([(3,16),(10,16)]); p.line([(18,11),(18,19)]); p.line([(14,15),(22,15)])
@glyph('text.badge.star')
def _(p):
    p.line([(3,6),(14,6)]); p.line([(3,11),(12,11)]); p.line([(3,16),(10,16)])
    pts=[]
    for k in range(10):
        a=math.radians(k*36-90); r=4 if k%2==0 else 1.7; pts.append((round(18+r*math.cos(a),2), round(16+r*math.sin(a),2)))
    p.line(pts, True)
@glyph('character', 'character.textbox')
def _(p): p.line([(5,20),(12,4),(19,20)]); p.line([(8,14),(16,14)])
@glyph('square.on.circle')
def _(p): p.circle(9,9,6); p.box(10,10,11,11)
@glyph('align.horizontal.center')
def _(p): p.line([(12,3),(12,21)]); p.box(6,6,12,4); p.box(8,14,8,4)
@glyph('square.3.layers.3d')
def _(p): p.line([(12,3),(21,7.5),(12,12),(3,7.5)], True); p.line([(3,12),(12,16.5),(21,12)]); p.line([(3,16.5),(12,21),(21,16.5)])
@glyph('square.2.layers.3d')
def _(p): p.line([(12,4),(21,8.5),(12,13),(3,8.5)], True); p.line([(3,14),(12,18.5),(21,14)])
@glyph('record.circle')
def _(p): p.circle(12,12,9); p.circle(12,12,4)
@glyph('stop.circle')
def _(p): p.circle(12,12,9); p.box(9,9,6,6)
@glyph('pause.circle')
def _(p): p.circle(12,12,9); p.line([(10,8.5),(10,15.5)]); p.line([(14,8.5),(14,15.5)])
@glyph('play.rectangle')
def _(p): p.box(3,5,18,14); p.line([(10,9),(15,12),(10,15)], True)
@glyph('waveform')
def _(p):
    for i,h in enumerate((4,8,13,17,10,6,14,8,4)): x=3+i*2.25; p.line([(x,12-h/2),(x,12+h/2)])
@glyph('waveform.badge.magnifyingglass')
def _(p):
    for i,h in enumerate((4,9,6)): x=3+i*2.5; p.line([(x,12-h/2),(x,12+h/2)])
    p.circle(15,12,4.5); p.line([(18.2,15.2),(21,18)])
@glyph('camera.filters')
def _(p): p.circle(12,8.5,5); p.circle(8.5,14.5,5); p.circle(15.5,14.5,5)
@glyph('camera.aperture')
def _(p):
    p.circle(12,12,9)
    for k in range(6):
        a=math.radians(k*60); b=math.radians(k*60+60)
        p.line([(round(12+9*math.cos(a),2),round(12+9*math.sin(a),2)),(round(12+3.5*math.cos(b),2),round(12+3.5*math.sin(b),2))])
@glyph('arrowtriangle.down')
def _(p): p.line([(5,8),(19,8),(12,17)], True)
@glyph('film')
def _(p):
    p.box(4,3,16,18); p.line([(8,3),(8,21)]); p.line([(16,3),(16,21)])
    for y in (8,12,16): p.line([(4,y),(8,y)]); p.line([(16,y),(20,y)])
@glyph('backward.frame')
def _(p): p.line([(5,5),(5,19)]); p.line([(19,5),(9,12),(19,19)], True)
@glyph('forward.frame')
def _(p): p.line([(19,5),(19,19)]); p.line([(5,5),(15,12),(5,19)], True)
@glyph('backward.end')
def _(p): p.line([(5,5),(5,19)]); p.line([(19,5),(9,12),(19,19)], True)
@glyph('arrow.triangle.2.circlepath')
def _(p): p.arc(12,12,8,200,340); p.line([(20.5,5.5),(19.5,9.3),(15.8,8.4)]); p.arc(12,12,8,20,160); p.line([(3.5,18.5),(4.5,14.7),(8.2,15.6)])
@glyph('arrow.triangle.branch')
def _(p): p.line([(12,21),(12,12),(5,5)]); p.line([(12,12),(19,5)]); p.line([(5,9),(5,5),(9,5)]); p.line([(15,5),(19,5),(19,9)])
@glyph('arrow.up.arrow.down')
def _(p): p.line([(8,20),(8,4)]); p.line([(4,8),(8,4),(12,8)]); p.line([(16,4),(16,20)]); p.line([(12,16),(16,20),(20,16)])
@glyph('arrow.up.right')
def _(p): p.line([(6,18),(18,6)]); p.line([(9,6),(18,6),(18,15)])
@glyph('arrow.down.left')
def _(p): p.line([(18,6),(6,18)]); p.line([(6,9),(6,18),(15,18)])
@glyph('arrow.right.to.line')
def _(p): p.line([(3,12),(15,12)]); p.line([(10,7),(15,12),(10,17)]); p.line([(20,4),(20,20)])
@glyph('arrow.down.right.and.arrow.up.left')
def _(p): p.line([(4,4),(10,10)]); p.line([(10,5.5),(10,10),(5.5,10)]); p.line([(20,20),(14,14)]); p.line([(14,18.5),(14,14),(18.5,14)])
@glyph('arrow.up.forward.square')
def _(p): p.box(3,3,18,18); p.line([(9,15),(15,9)]); p.line([(10,9),(15,9),(15,14)])
@glyph('arrow.uturn.backward.circle')
def _(p): p.circle(12,12,9); p.line([(8,10),(13,10)]); p.arc(13,13,3,-90,90,False); p.line([(13,16),(10,16)]); p.line([(10,7.5),(8,10),(10,12.5)])
@glyph('arrow.uturn.right.circle')
def _(p): p.circle(12,12,9); p.line([(16,10),(11,10)]); p.arc(11,13,3,270,90,False); p.line([(11,16),(14,16)]); p.line([(14,7.5),(16,10),(14,12.5)])
@glyph('arrowshape.turn.up.left')
def _(p): p.line([(10,4),(3,10),(10,16),(10,12.5)]); p.quad(21,19,18,12); p.quad(10,7.5,19,7); p.close()
@glyph('bell.badge')
def _(p): bell(p); p.circle(18.5,5,2.5)
@glyph('note.text')
def _(p): p.box(4,4,16,16); p.line([(8,9),(16,9)]); p.line([(8,13),(16,13)]); p.line([(8,17),(13,17)])
@glyph('brain')
def _(p): p.circle(12,12,8.5); p.line([(12,3.5),(12,20.5)]); p.arc(8,9.5,2.5,-60,120); p.arc(16,14.5,2.5,120,300)
@glyph('hand.raised')
def _(p):
    p.line([(7,14),(7,6.5),(9,6.5),(9,11)]); p.line([(9,11),(9,4),(11,4),(11,11)]); p.line([(11,11),(11,4.5),(13,4.5),(13,11)])
    p.line([(13,11),(13,6),(15,6),(15,13),(17.5,10.5),(19,12),(15,19),(9,20),(7,17),(7,14)])
@glyph('flag.checkered')
def _(p): p.line([(5,21),(5,4)]); p.box(5,4,13,9); p.line([(11.5,4),(11.5,13)]); p.line([(5,8.5),(18,8.5)])
@glyph('bandage')
def _(p): p.line([(4,14),(14,4),(20,10),(10,20)], True); p.circle(11,12,0.4); p.circle(13,12,0.4); p.circle(12,11,0.4); p.circle(12,13,0.4)
@glyph('c.square')
def _(p): p.box(4,4,16,16); p.arc(12,12,4,45,315)
@glyph('cube')
def _(p): p.line([(12,3),(20,7.5),(20,16.5),(12,21),(4,16.5),(4,7.5)], True); p.line([(4,7.5),(12,12),(20,7.5)]); p.line([(12,12),(12,21)])
@glyph('cursorarrow')
def _(p): p.line([(6,3),(6,19),(10,15),(13,21),(15.5,20),(12.5,14),(18,14)], True)
@glyph('graduationcap')
def _(p): p.line([(2,9),(12,4),(22,9),(12,14)], True); p.line([(6,11),(6,16)]); p.arc(12,13,6,0,180,True); p.line([(22,9),(22,15)])
@glyph('hammer')
def _(p): p.line([(4,20),(13,11)]); p.line([(10,8),(14,4),(19,5),(16,8),(20,12),(17,15),(13,11)], True)
@glyph('highlighter')
def _(p): p.line([(8,15),(17,6),(20,9),(11,18)], True); p.line([(8,15),(6,17),(8,19),(11,18)]); p.line([(4,21),(9,21)])
@glyph('key')
def _(p): p.circle(8,12,4); p.line([(12,12),(21,12)]); p.line([(17,12),(17,15)]); p.line([(20,12),(20,14)])
@glyph('line.diagonal')
def _(p): p.line([(5,19),(19,5)])
@glyph('megaphone')
def _(p): p.line([(3,10),(7,10),(18,4),(18,20),(7,14),(3,14)], True); p.line([(7,10),(7,14)]); p.line([(7,14),(9,20),(12,20),(10.5,15.5)])
@glyph('moon.stars')
def _(p):
    p.arc(11,13,7.5,14.8,262); p.arc(15,9.5,6.4,217.8,58.9,False); p.close()
    p.line([(18,3),(18,7)]); p.line([(16,5),(20,5)])
@glyph('newspaper')
def _(p): p.line([(5,4),(19,4),(19,20),(5,20)], True); p.box(8,7,8,4); p.line([(8,14),(16,14)]); p.line([(8,17),(14,17)])
@glyph('photo.on.rectangle')
def _(p): p.line([(3,16),(3,4),(17,4)]); p.box(7,8,14,12); p.line([(7,18),(11,14),(14,17),(16,15),(21,19)])
@glyph('qrcode')
def _(p): p.box(3,3,7,7); p.box(14,3,7,7); p.box(3,14,7,7); p.box(5.5,5.5,2,2); p.box(16.5,5.5,2,2); p.box(5.5,16.5,2,2); p.line([(14,14),(14,17)]); p.line([(17,14),(21,14)]); p.line([(17,17),(17,21),(21,21),(21,17)])
@glyph('safari')
def _(p): p.circle(12,12,9); p.line([(15.5,8.5),(13,13),(8.5,15.5),(11,11)], True)
@glyph('scope')
def _(p): p.circle(12,12,8); p.circle(12,12,3); p.line([(12,2),(12,6)]); p.line([(12,18),(12,22)]); p.line([(2,12),(6,12)]); p.line([(18,12),(22,12)])
@glyph('scribble')
def _(p): p.move(3,16); p.quad(9,7,4,6); p.quad(12,15,10,15); p.quad(17,6,13,6); p.quad(21,13,21,8)
@glyph('signature')
def _(p): p.move(3,16); p.quad(8,6,5,4); p.quad(9,17,11,9); p.quad(14,12,12,14); p.quad(21,14,16,11); p.line([(3,20.5),(21,20.5)])
@glyph('sun.horizon')
def _(p):
    p.arc(12,16,5,180,360); p.line([(2,16),(22,16)]); p.line([(6,20),(18,20)])
    for a in (180,225,270,315,360):
        r=math.radians(a); p.line([(round(12+7.5*math.cos(r),2),round(16+7.5*math.sin(r),2)),(round(12+9.5*math.cos(r),2),round(16+9.5*math.sin(r),2))])
@glyph('sun.max')
def _(p):
    p.circle(12,12,4.5)
    for k in range(8):
        r=math.radians(k*45); p.line([(round(12+7*math.cos(r),2),round(12+7*math.sin(r),2)),(round(12+9.5*math.cos(r),2),round(12+9.5*math.sin(r),2))])
@glyph('cloud')
def _(p): cloud(p)
@glyph('cloud.sun')
def _(p):
    p.arc(9,8,3.5,150,390)
    for a in (180,225,270,315): r=math.radians(a); p.line([(round(9+5*math.cos(r),2),round(8+5*math.sin(r),2)),(round(9+6.8*math.cos(r),2),round(8+6.8*math.sin(r),2))])
    cloud(p, 3)
@glyph('cloud.rain', 'cloud.drizzle')
def _(p): cloud(p,-3); p.line([(8,17),(7,20)]); p.line([(12,17),(11,20)]); p.line([(16,17),(15,20)])
@glyph('cloud.snow')
def _(p): cloud(p,-3); p.circle(8,18.5,0.5); p.circle(12,20,0.5); p.circle(16,18.5,0.5); p.circle(10,21.5,0.5); p.circle(14,21.5,0.5)
@glyph('cloud.fog')
def _(p): cloud(p,-3); p.line([(5,17),(19,17)]); p.line([(7,20.5),(17,20.5)])
@glyph('cloud.bolt.rain', 'cloud.bolt')
def _(p): cloud(p,-3); p.line([(13,15),(10,19),(14,19),(11,22.5)]); p.line([(7,17),(6,20)]); p.line([(18,17),(17,20)])
@glyph('terminal')
def _(p): p.box(3,4,18,16); p.line([(7,9),(10,12),(7,15)]); p.line([(12,15.5),(17,15.5)])
@glyph('chevron.left.forwardslash.chevron.right')
def _(p): p.line([(7,7),(2.5,12),(7,17)]); p.line([(17,7),(21.5,12),(17,17)]); p.line([(14,5),(10,19)])
@glyph('pencil.line')
def _(p): p.line([(15,3),(19,7),(9,17),(5,17),(5,13)], True); p.line([(12.5,5.5),(16.5,9.5)]); p.line([(3,21),(21,21)])
@glyph('xmark.octagon')
def _(p): p.line([(8.3,3),(15.7,3),(21,8.3),(21,15.7),(15.7,21),(8.3,21),(3,15.7),(3,8.3)], True); p.line([(9,9),(15,15)]); p.line([(15,9),(9,15)])
@glyph('tray')
def _(p): p.line([(3,13),(8,13),(9.5,16),(14.5,16),(16,13),(21,13)]); p.line([(3,13),(5.5,5),(18.5,5),(21,13),(21,20),(3,20)], True)
@glyph('inbox')
def _(p): p.line([(3,13),(8,13),(9.5,16),(14.5,16),(16,13),(21,13)]); p.line([(3,13),(5.5,5),(18.5,5),(21,13),(21,20),(3,20)], True)
@glyph('crop')
def _(p): p.line([(6,2),(6,18),(22,18)]); p.line([(2,6),(18,6),(18,22)])

def swift_num(v):
    v=round(float(v),2)
    return str(int(v)) if v==int(v) else ("%g" % v)
def emit(name, f):
    p=Pen(); f(p); parts=[]
    for op in p.ops:
        k=op[0]
        if k=='line':
            pts=", ".join(f"({swift_num(x)}, {swift_num(y)})" for x,y in op[1])
            parts.append(f"pen.line([{pts}]{', closed: true' if op[2] else ''})")
        elif k=='box': parts.append("pen.box(%s)" % ", ".join(swift_num(v) for v in op[1:]))
        elif k=='circle': parts.append("pen.circle(%s)" % ", ".join(swift_num(v) for v in op[1:]))
        elif k=='ellipse': parts.append("pen.ellipse(%s)" % ", ".join(swift_num(v) for v in op[1:]))
        elif k=='rrect': parts.append("pen.rrect(%s)" % ", ".join(swift_num(v) for v in op[1:]))
        elif k=='arc': parts.append(f"pen.arc({swift_num(op[1])}, {swift_num(op[2])}, {swift_num(op[3])}, from: {swift_num(op[4])}, to: {swift_num(op[5])}{'' if op[6] else ', start: false'})")
        elif k=='move': parts.append(f"pen.move({swift_num(op[1])}, {swift_num(op[2])})")
        elif k=='quad': parts.append(f"pen.quad({swift_num(op[1])}, {swift_num(op[2])}, control: ({swift_num(op[3])}, {swift_num(op[4])}))")
        elif k=='close': parts.append("pen.close()")
    return p, parts

def swift():
    names=sorted(G)
    out=['import SwiftUI','','// Generated by sandbox/tools/glyphs.py; edit the definitions there. 1.5pt ink lines on a 24-point square.','',
         '/// The rest of the action icons, drawn in the brand\'s line: everything the apps use that the first set didn\'t cover.',
         'enum MoreGlyphs {', '    static let names: Set<String> = [']
    line='       '
    for n in names:
        piece=f' "{n}",'
        if len(line)+len(piece)>118: out.append(line); line='       '
        line+=piece
    out.append(line); out.append('    ]'); out.append('')
    out.append('    static func path(_ name: String) -> Path {')
    out.append('        var pen = GlyphPen()')
    out.append('        switch name {')
    for n in names:
        _,parts=emit(n,G[n])
        out.append(f'        case "{n}":')
        for part in parts: out.append('            '+part)
    out.append('        default: break'); out.append('        }'); out.append('        return pen.path'); out.append('    }'); out.append('}'); out.append('')
    out.append('''/// Draws the glyphs: straight lines, boxes, circles, arcs in degrees (clockwise from three o'clock, y down) and curves.
struct GlyphPen {
    var path = Path()

    mutating func line(_ points: [(CGFloat, CGFloat)], closed: Bool = false) {
        guard let first = points.first else { return }
        path.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        if closed { path.closeSubpath() }
    }

    mutating func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        path.addRect(CGRect(x: x, y: y, width: width, height: height))
    }

    mutating func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
        path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

    mutating func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        path.addEllipse(in: CGRect(x: x, y: y, width: width, height: height))
    }

    mutating func rrect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) {
        path.addRoundedRect(in: CGRect(x: x, y: y, width: width, height: height), cornerSize: CGSize(width: radius, height: radius))
    }

    mutating func arc(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat, from: CGFloat, to: CGFloat, start: Bool = true) {
        let steps = 24
        for step in 0...steps {
            let angle = (from + (to - from) * CGFloat(step) / CGFloat(steps)) * .pi / 180
            let point = CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
            if step == 0 && start { path.move(to: point) } else { path.addLine(to: point) }
        }
    }

    mutating func move(_ x: CGFloat, _ y: CGFloat) { path.move(to: CGPoint(x: x, y: y)) }

    mutating func quad(_ x: CGFloat, _ y: CGFloat, control: (CGFloat, CGFloat)) {
        path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: control.0, y: control.1))
    }

    mutating func close() { path.closeSubpath() }
}''')
    return "\n".join(out)+"\n"

def render(path, S=6, cols=10):
    from PIL import Image, ImageDraw, ImageFont
    names=sorted(G); cell=24*S+40; rows=(len(names)+cols-1)//cols
    img=Image.new('RGB',(cols*cell, rows*(cell+16)),'white'); d=ImageDraw.Draw(img)
    w=max(1,round(1.5*S))
    for i,n in enumerate(names):
        ox=(i%cols)*cell+20; oy=(i//cols)*(cell+16)+8
        p=Pen(); G[n](p)
        cur=None; start=None
        def P(x,y): return (ox+x*S, oy+y*S)
        def poly(pts, closed=False):
            if closed: pts=pts+[pts[0]]
            d.line([P(*q) for q in pts], fill='black', width=w, joint='curve')
            for q in (pts[0], pts[-1]):
                x,y=P(*q); d.ellipse([x-w/2,y-w/2,x+w/2,y+w/2], fill='black')
        last=None
        for op in p.ops:
            k=op[0]
            if k=='line': poly(op[1], op[2]); last=op[1][-1]
            elif k=='box': x,y,ww,hh=op[1:]; poly([(x,y),(x+ww,y),(x+ww,y+hh),(x,y+hh)], True)
            elif k=='circle': x,y,r=op[1:]; d.ellipse([*P(x-r,y-r),*P(x+r,y+r)], outline='black', width=w) if r>0.6 else d.ellipse([*P(x-r-0.4,y-r-0.4),*P(x+r+0.4,y+r+0.4)], fill='black')
            elif k=='ellipse': x,y,ww,hh=op[1:]; d.ellipse([*P(x,y),*P(x+ww,y+hh)], outline='black', width=w)
            elif k=='rrect': x,y,ww,hh,r=op[1:]; d.rounded_rectangle([*P(x,y),*P(x+ww,y+hh)], radius=r*S, outline='black', width=w)
            elif k=='arc':
                cx,cy,r,a,b,st=op[1:]
                pts=[(cx+r*math.cos(math.radians(a+(b-a)*t/24)), cy+r*math.sin(math.radians(a+(b-a)*t/24))) for t in range(25)]
                if not st and last: pts=[last]+pts
                poly(pts); last=pts[-1]
            elif k=='move': last=(op[1],op[2]); start=last
            elif k=='quad':
                x,y,cx,cy=op[1:]; x0,y0=last
                pts=[((1-t)**2*x0+2*(1-t)*t*cx+t*t*x, (1-t)**2*y0+2*(1-t)*t*cy+t*t*y) for t in [i/20 for i in range(21)]]
                poly(pts); last=(x,y)
            elif k=='close':
                pass
        d.rectangle([ox-2,oy-2,ox+24*S+2,oy+24*S+2], outline=(225,225,225))
        d.text((ox, oy+24*S+4), n[:26], fill='black')
    img.save(path)

if __name__=='__main__':
    if sys.argv[1]=='swift': open(sys.argv[2],'w').write(swift())
    else: render(sys.argv[2])
    print(len(G),'glyphs')
