import { useCallback } from 'react';
import { FlatList, SafeAreaView, StyleSheet, Text, View } from 'react-native';
import { TurboHtmlView, type LinkPressEvent } from 'react-native-turbo-html';

type Row = {
  id: string;
  label: string;
  html: string;
  numberOfLines?: number;
};

// A grab-bag of every rendering rule the package documents: English + Khmer, bold /
// italic / underline / strike, <br>, lists, links (including www./tel: detection) and one
// row with numberOfLines to exercise truncation.
const SAMPLES: Omit<Row, 'id'>[] = [
  {
    label: 'Plain paragraph',
    html: '<p>Hello world. This is a plain paragraph of body text.</p>',
  },
  {
    label: 'Bold / italic / underline / strike',
    html: '<p><b>Bold</b>, <i>italic</i>, <u>underline</u>, <s>strikethrough</s>, and <b><i>bold italic</i></b>.</p>',
  },
  {
    label: 'Headings',
    html: '<h1>Heading 1</h1><h3>Heading 3</h3><p>Body text below a heading.</p>',
  },
  {
    label: 'Line breaks',
    html: '<p>First line<br/>Second line<br/>Third line</p>',
  },
  {
    label: 'Unordered list',
    html: '<ul><li>Parking included</li><li>Near school</li><li>Pet friendly</li></ul>',
  },
  {
    label: 'Ordered list',
    html: '<ol><li>Sign the lease</li><li>Pay the deposit</li><li>Move in</li></ol>',
  },
  {
    label: 'Links (http / www. / mailto)',
    html: '<p>Visit <a href="https://turbo.com">our site</a>, or <a href="www.example.com">www.example.com</a>, or email <a href="mailto:hello@turbo.com">hello@turbo.com</a>.</p>',
  },
  {
    label: 'Phone number detection',
    html: '<p>Call us at 012 345 678 or +855 12 345 678 for more information.</p>',
  },
  {
    label: 'Khmer text',
    html: '<p>ផ្ទះល្វែងលក់បន្ទាន់ នៅជិតផ្សារ <strong>Tuol Kork</strong>។ តម្លៃ <em>$120,000</em>។ ទំហំ 4x16m។</p>',
  },
  {
    label: 'Khmer heading + list',
    html: '<h2>លក្ខណៈពិសេស</h2><ul><li>3 បន្ទប់គេង</li><li>2 បន្ទប់ទឹក</li></ul>',
  },
  {
    label: 'Mixed HTML + phone + link',
    html: '<p>ផ្ទះល្វែងលក់បន្ទាន់ នៅជិតផ្សារ <strong>Tuol Kork</strong> តម្លៃ <em>$120,000</em> &amp; negotiable. Call 012 345 678 or <a href="https://turbo.com/x?a=1&amp;b=2">view listing</a>.<br/>ទំហំ 4x16m, 3 bedrooms, 2 bathrooms.</p>',
  },
  {
    label: 'Truncated to 2 lines (numberOfLines=2)',
    html:
      '<p>' +
      'This paragraph is deliberately long so that it wraps across many lines and gets truncated with an ellipsis after only two lines are shown, no matter how much more text follows it in the source HTML.'.repeat(
        2
      ) +
      '</p>',
    numberOfLines: 2,
  },
  {
    label: 'Nested wrapper (no extra gap)',
    html: '<div><p>First paragraph inside a div.</p><p>Second paragraph inside the same div.</p></div><p>A separate top-level paragraph.</p>',
  },
  {
    label: 'Entities',
    html: '<p>Tom &amp; Jerry &mdash; &ldquo;quoted&rdquo; &hellip;</p>',
  },
];

// Repeat the sample set to make a ~50-row scrollable FlatList.
const ROWS: Row[] = Array.from({ length: 50 }, (_, index) => {
  const sample = SAMPLES[index % SAMPLES.length]!;
  return { id: String(index), ...sample };
});

function Row({
  item,
  onLinkPress,
}: {
  item: Row;
  onLinkPress: (event: LinkPressEvent) => void;
}) {
  const handlePress = useCallback(
    (event: { nativeEvent: LinkPressEvent }) => onLinkPress(event.nativeEvent),
    [onLinkPress]
  );
  return (
    <View style={styles.row}>
      <Text style={styles.label}>
        #{item.id} · {item.label}
      </Text>
      <TurboHtmlView
        html={item.html}
        fontFamily="System"
        fontSize={15}
        lineHeight={22}
        numberOfLines={item.numberOfLines ?? 0}
        detectPhoneNumbers
        onLinkPress={handlePress}
        style={styles.htmlView}
      />
    </View>
  );
}

export default function App() {
  const onLinkPress = useCallback((event: LinkPressEvent) => {
    console.log('onLinkPress', event.type, event.url);
  }, []);

  return (
    <SafeAreaView style={styles.container}>
      <FlatList
        data={ROWS}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => <Row item={item} onLinkPress={onLinkPress} />}
        contentContainerStyle={styles.list}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#ffffff',
  },
  list: {
    paddingVertical: 8,
  },
  row: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#e0e0e0',
  },
  label: {
    fontSize: 11,
    fontWeight: '600',
    color: '#04ab52',
    marginBottom: 4,
    textTransform: 'uppercase',
  },
  htmlView: {
    width: '100%',
  },
});
