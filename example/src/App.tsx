import { useState, useEffect } from 'react';
import { StyleSheet, View, Text } from 'react-native';
import L from 'react-native-local-model';

export default function App() {
  const [result, setResult] = useState<number | undefined>();

  useEffect(() => {
    (async () => {
      try {
        console.log('WROKING');
        const load = await L.loadModelAndAskQuestion(
          'sample_model',
          'How are you doing?'
        );
        console.log('RESPONSE', load);
      } catch (e) {
        console.log('ERROR', e);
      }
    })();
  }, []);
  return (
    <View style={styles.container}>
      <Text>Result: {result}</Text>
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
