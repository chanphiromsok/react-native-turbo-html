// https://github.com/react-native-community/cli/blob/main/docs/dependencies.md
module.exports = {
  dependency: {
    platforms: {
      ios: {},
      android: {
        packageImportPath: 'import com.turbohtml.TurboHtmlPackage;',
        packageInstance: 'new TurboHtmlPackage()',
        // Hand-written descriptor (measuring ShadowNode) instead of a codegen one.
        componentDescriptors: ['TurboHtmlViewComponentDescriptor'],
        cmakeListsPath: '../android/src/main/jni/CMakeLists.txt',
      },
    },
  },
};
