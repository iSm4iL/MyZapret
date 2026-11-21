using System;
using System.IO;
using System.Diagnostics;
using System.ServiceProcess;
using System.Web.Script.Serialization;
using System.Runtime.InteropServices;

public sealed class EngineService : ServiceBase {
    sealed class Config { public string FileName; public string Arguments; public string WorkingDirectory; }
    readonly string configPath;
    Process child;
    IntPtr job;
    bool stopping;
    string log;
    [StructLayout(LayoutKind.Sequential)] struct BasicLimits {
        public long ProcessTime, JobTime; public uint Flags; public UIntPtr Min, Max;
        public uint Active; public UIntPtr Affinity; public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong A,B,C,D,E,F; }
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimits {
        public BasicLimits Basic; public IoCounters Io;
        public UIntPtr ProcessMemory,JobMemory,PeakProcess,PeakJob;
    }
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr a,string n);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr j,int c,ref ExtendedLimits i,uint l);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr j,IntPtr p);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    static readonly object gate=new object();
    EngineService(string path) {configPath=path;ServiceName="MyZapretEngine";CanStop=true;}
    void Write(string s) {lock(gate){File.AppendAllText(log,DateTime.Now.ToString("s")+" "+s+Environment.NewLine);}}
    protected override void OnStart(string[] args) {
        log=configPath+".log";
        try {
            var c=new JavaScriptSerializer().Deserialize<Config>(File.ReadAllText(configPath));
            if(c==null || !File.Exists(c.FileName)) throw new IOException("Engine executable is missing");
            job=CreateJobObject(IntPtr.Zero,null);
            var limits=new ExtendedLimits();limits.Basic.Flags=0x2000; // Kill child processes if the service exits.
            if(job==IntPtr.Zero || !SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf(limits)))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            var info=new ProcessStartInfo(c.FileName,c.Arguments) {WorkingDirectory=c.WorkingDirectory,
                UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
            child=new Process {StartInfo=info,EnableRaisingEvents=true};
            child.OutputDataReceived+=(s,e)=>{if(e.Data!=null)Write(e.Data);};
            child.ErrorDataReceived+=(s,e)=>{if(e.Data!=null)Write(e.Data);};
            child.Start();
            if(!AssignProcessToJobObject(job,child.Handle))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            child.BeginOutputReadLine();child.BeginErrorReadLine();
            if(child.WaitForExit(2000)) throw new IOException("Engine exited during startup: "+child.ExitCode);
            child.Exited+=(s,e)=>{if(!stopping){Write("Engine exited: "+child.ExitCode);ExitCode=1067;Stop();}};
            Write("Engine running; PID="+child.Id);
            if(child.HasExited) throw new IOException("Engine exited during startup");
        } catch(Exception e) {Write(e.ToString());Cleanup();throw;}
    }
    void Cleanup() {
        stopping=true;
        if(job!=IntPtr.Zero){CloseHandle(job);job=IntPtr.Zero;}
        if(child!=null){try{if(!child.HasExited)child.Kill();child.WaitForExit(5000);}catch(InvalidOperationException){}child.Dispose();child=null;}
    }
    protected override void OnStop(){Cleanup();}
    protected override void OnShutdown(){Cleanup();}
    static void Main(string[] args){if(args.Length!=1)Environment.Exit(2);ServiceBase.Run(new EngineService(args[0]));}
}
