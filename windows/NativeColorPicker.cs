using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
namespace KarimEldamatyWindows;
internal static class NativeColorPicker
{
    [StructLayout(LayoutKind.Sequential)]private struct ChooseColour{public int Size;public IntPtr Owner,Instance;public uint Result;public IntPtr Custom;public uint Flags;public IntPtr Data,Hook,Template;}
    [DllImport("comdlg32.dll",CharSet=CharSet.Unicode,EntryPoint="ChooseColorW")]private static extern bool ChooseColor(ref ChooseColour colour);
    public static InkColor? Pick(Window owner,InkColor initial){var memory=Marshal.AllocHGlobal(16*4);try{for(var i=0;i<16;i++)Marshal.WriteInt32(memory,i*4,0x00FFFFFF);var c=initial.Wpf;var request=new ChooseColour{Size=Marshal.SizeOf<ChooseColour>(),Owner=new WindowInteropHelper(owner).Handle,Result=(uint)(c.R|(c.G<<8)|(c.B<<16)),Custom=memory,Flags=0x1|0x2};return ChooseColor(ref request)?new InkColor((request.Result&255)/255d,((request.Result>>8)&255)/255d,((request.Result>>16)&255)/255d,initial.A):null;}finally{Marshal.FreeHGlobal(memory);}}
}
