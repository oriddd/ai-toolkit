import { Text, TextInput } from 'react-native';
import { Controller, type Control, type FieldPath, type FieldValues } from 'react-hook-form';

type Props<T extends FieldValues> = {
  control: Control<T>;
  name: FieldPath<T>;
  label: string;
  testID: string;
  secureTextEntry?: boolean;
};

export function FormTextField<T extends FieldValues>({ control, name, label, testID, secureTextEntry = false }: Props<T>) {
  return (
    <Controller
      control={control}
      name={name}
      render={({ field, fieldState }) => (
        <>
          <Text>{label}</Text>
          <TextInput
            accessibilityLabel={label}
            testID={testID}
            secureTextEntry={secureTextEntry}
            autoCapitalize="none"
            value={typeof field.value === 'string' ? field.value : ''}
            onBlur={field.onBlur}
            onChangeText={field.onChange}
          />
          {fieldState.error ? <Text accessibilityRole="alert">{fieldState.error.message}</Text> : null}
        </>
      )}
    />
  );
}
