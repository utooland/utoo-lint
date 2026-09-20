function read<T>(value:T):T{return value;}
function example(value:any,items:any[]){let total=1; total+=value; return read(value)+items[0];}
