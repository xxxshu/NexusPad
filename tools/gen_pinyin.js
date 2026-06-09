#!/usr/bin/env node
/**
 * Generate combined pinyin dictionary (characters + words).
 * Input:  char pinyin.txt (mozillazg/pinyin-data)
 *         phrase pinyin.txt (mozillazg/phrase-pinyin-data)
 * Output: frontend/pinyin-dict.js
 *
 * Usage: node tools/gen_pinyin.js <char_file> <phrase_file> <output_file>
 */

const fs = require('fs');

const charFile = process.argv[2] || '/tmp/pinyin.txt';
const phraseFile = process.argv[3] || '/tmp/phrase_pinyin.txt';
const outputFile = process.argv[4] || 'frontend/pinyin-dict.js';

// Valid pinyin syllables
const VALID = new Set([
  'a','ai','an','ang','ao','ba','bai','ban','bang','bao','bei','ben','beng','bi','bian','biao','bie','bin','bing','bo','bu',
  'ca','cai','can','cang','cao','ce','cen','ceng','cha','chai','chan','chang','chao','che','chen','cheng','chi','chong','chou','chu','chua','chuai','chuan','chuang','chui','chun','chuo','ci','cong','cou','cu','cuan','cui','cun','cuo',
  'da','dai','dan','dang','dao','de','dei','den','deng','di','dian','diao','die','ding','diu','dong','dou','du','duan','dui','dun','duo',
  'e','ei','en','eng','er',
  'fa','fan','fang','fei','fen','feng','fiao','fo','fou','fu',
  'ga','gai','gan','gang','gao','ge','gei','gen','geng','gong','gou','gu','gua','guai','guan','guang','gui','gun','guo',
  'ha','hai','han','hang','hao','he','hei','hen','heng','hong','hou','hu','hua','huai','huan','huang','hui','hun','huo',
  'ji','jia','jian','jiang','jiao','jie','jin','jing','jiong','jiu','ju','juan','jue','jun',
  'ka','kai','kan','kang','kao','ke','kei','ken','keng','kong','kou','ku','kua','kuai','kuan','kuang','kui','kun','kuo',
  'la','lai','lan','lang','lao','le','lei','leng','li','lia','lian','liang','liao','lie','lin','ling','liu','lo','long','lou','lu','luan','lun','luo','lv','lve',
  'ma','mai','man','mang','mao','me','mei','men','meng','mi','mian','miao','mie','min','ming','miu','mo','mou','mu',
  'na','nai','nan','nang','nao','ne','nei','nen','neng','ni','nian','niang','niao','nie','nin','ning','niu','nong','nou','nu','nuan','nuo','nv','nve',
  'o','ou',
  'pa','pai','pan','pang','pao','pei','pen','peng','pi','pian','piao','pie','pin','ping','po','pou','pu',
  'qi','qia','qian','qiang','qiao','qie','qin','qing','qiong','qiu','qu','quan','que','qun',
  'ran','rang','rao','re','ren','reng','ri','rong','rou','ru','rua','ruan','rui','run','ruo',
  'sa','sai','san','sang','sao','se','sen','seng','sha','shai','shan','shang','shao','she','shei','shen','sheng','shi','shou','shu','shua','shuai','shuan','shuang','shui','shun','shuo','si','song','sou','su','suan','sui','sun','suo',
  'ta','tai','tan','tang','tao','te','teng','ti','tian','tiao','tie','ting','tong','tou','tu','tuan','tui','tun','tuo',
  'wa','wai','wan','wang','wei','wen','weng','wo','wu',
  'xi','xia','xian','xiang','xiao','xie','xin','xing','xiong','xiu','xu','xuan','xue','xun',
  'ya','yan','yang','yao','ye','yi','yin','ying','yong','you','yu','yuan','yue','yun',
  'za','zai','zan','zang','zao','ze','zei','zen','zeng','zha','zhai','zhan','zhang','zhao','zhe','zhen','zheng','zhi','zhong','zhou','zhu','zhua','zhuai','zhuan','zhuang','zhui','zhun','zhuo','zi','zong','zou','zu','zuan','zui','zun','zuo',
  'm','n','ng','er'
]);

function stripTone(py) {
  return py.normalize('NFD').replace(/\p{M}/gu, '').normalize('NFC').toLowerCase().trim();
}

function parsePinyin(pyStr) {
  return pyStr.split(/[\s,]+/).map(s => stripTone(s)).filter(s => s && VALID.has(s));
}

// ── Process character-level data ──
const charMap = {}; // pinyin → array of characters
const charLines = fs.readFileSync(charFile, 'utf-8').split('\n');
for (const line of charLines) {
  if (line.startsWith('#') || !line.trim()) continue;
  const m = line.match(/U\+[0-9A-F]+:\s*(.+?)\s+#\s+(.)/);
  if (!m) continue;
  const char = m[2];
  const code = char.codePointAt(0);
  if (code < 0x4E00 || code > 0x9FFF) continue;
  const pys = parsePinyin(m[1]);
  for (const py of pys) {
    if (!charMap[py]) charMap[py] = [];
    if (!charMap[py].includes(char)) charMap[py].push(char);
  }
}

// ── Process phrase-level data ──
const wordMap = {}; // concatenated pinyin → array of words
const phraseLines = fs.readFileSync(phraseFile, 'utf-8').split('\n');
for (const line of phraseLines) {
  if (line.startsWith('#') || !line.trim()) continue;
  const idx = line.indexOf(':');
  if (idx < 0) continue;
  const word = line.substring(0, idx).trim();
  const pyStr = line.substring(idx + 1).trim();
  // Only CJK characters
  if (!/^[一-鿿]+$/.test(word)) continue;
  if (word.length < 2 || word.length > 6) continue; // 2-6 char words
  const pys = parsePinyin(pyStr);
  if (pys.length !== word.length) continue; // pinyin count must match char count
  const key = pys.join('');
  if (!wordMap[key]) wordMap[key] = [];
  if (!wordMap[key].includes(word)) wordMap[key].push(word);
}

// ── Merge: words have priority over single chars ──
// Keys like "nihao" → words first, then individual chars
const merged = {};

// Add single-char entries (1-syllable keys)
for (const [py, chars] of Object.entries(charMap)) {
  merged[py] = chars.join('');
}

// Add word entries (multi-syllable keys) — words go first
for (const [key, words] of Object.entries(wordMap)) {
  if (merged[key]) {
    // Prepend words before existing chars
    merged[key] = words.join('') + merged[key];
  } else {
    merged[key] = words.join('');
  }
}

// ── Output ──
const entries = Object.entries(merged).sort((a, b) => a[0].localeCompare(b[0]));
let js = '// Auto-generated: characters (mozillazg/pinyin-data) + words (mozillazg/phrase-pinyin-data)\n';
js += 'var PINYIN_MAP = {\n';
for (const [py, val] of entries) {
  // Escape any special chars in the key
  js += `"${py}":"${val}",`;
}
js += '\n};\n';

fs.writeFileSync(outputFile, js);

const charCount = Object.values(charMap).reduce((s, a) => s + a.length, 0);
const wordCount = Object.values(wordMap).reduce((s, a) => s + a.length, 0);
console.log(`Generated ${outputFile}:`);
console.log(`  Characters: ${Object.keys(charMap).length} syllables, ${charCount} chars`);
console.log(`  Words: ${Object.keys(wordMap).length} keys, ${wordCount} words`);
console.log(`  Merged: ${entries.length} total keys`);
console.log(`  File size: ${(js.length / 1024).toFixed(1)} KB`);
