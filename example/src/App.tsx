import { View, StyleSheet } from 'react-native';
import { TurboHtmlView } from 'react-native-turbo-html';

export default function App() {
  return (
    <View style={styles.container}>
      <TurboHtmlView color="#32a852" style={styles.box} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  box: {
    width: 60,
    height: 60,
    marginVertical: 20,
  },
});
